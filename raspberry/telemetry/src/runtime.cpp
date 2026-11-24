#include "runtime.hpp"
#include "local_control.hpp"

#include <algorithm>
#include <chrono>
#include <exception>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>
#include <regex>
#include <utility>
#include <unistd.h>
#include <nlohmann/json.hpp>

namespace pocketnet::telemetry {
namespace {
using Clock = std::chrono::steady_clock;
using namespace std::chrono_literals;
constexpr std::size_t kPending = 128;

v1::MonitoringEvent notice(const std::string& type, v1::EventPriority priority,
                           const std::string& source, const std::string& description) {
    v1::MonitoringEvent event;
    event.set_timestamp_ms(wall_ms());
    event.set_event_type(type);
    event.set_priority(priority);
    event.set_source(source);
    event.set_description(description);
    event.set_event_category(type == "priority_ap_observed" ? v1::OBSERVATION :
        (type.find("sampling_") == 0 ? v1::DATA_QUALITY : v1::DEVICE_HEALTH));
    event.set_risk_class(v1::INFO);
    event.set_observed_at_ms(event.timestamp_ms());
    return event;
}

std::uint64_t resident_set_bytes() {
    std::ifstream statm("/proc/self/statm");
    std::uint64_t total_pages = 0, resident_pages = 0;
    if (!(statm >> total_pages >> resident_pages)) return 0;
    (void)total_pages;
    const long page_size = ::sysconf(_SC_PAGESIZE);
    if (page_size <= 0) return 0;
    return resident_pages * static_cast<std::uint64_t>(page_size);
}

bool same_notice(const v1::MonitoringEvent& lhs, const v1::MonitoringEvent& rhs) {
    if (!lhs.evidence_id().empty() || !rhs.evidence_id().empty()) {
        return !lhs.evidence_id().empty() && lhs.source() == rhs.source() &&
               lhs.evidence_id() == rhs.evidence_id();
    }
    return lhs.event_type() == rhs.event_type() && lhs.source() == rhs.source() &&
           lhs.bssid() == rhs.bssid() && lhs.description() == rhs.description();
}
}  // namespace

std::int64_t wall_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

Runtime::Runtime(EventStore& events, KismetCollector kismet, std::string boot_id,
                 std::string device_boot_id, HighRiskOutbox* outbox)
    : events_(events), kismet_(std::move(kismet)), boot_id_(std::move(boot_id)),
      device_boot_id_(std::move(device_boot_id)), outbox_(outbox) {
    capture_.set_datasource_state("starting");
    capture_.set_coverage("unavailable");
    snapshot_.set_boot_id(boot_id_);
    snapshot_.set_schema_version(1);
    snapshot_.set_timestamp_ms(wall_ms());
    snapshot_.set_latest_event_sequence(events_.latest());
    *snapshot_.mutable_capture() = capture_;
    try {
        system_worker_ = std::thread(&Runtime::sample_system, this);
        alert_worker_ = std::thread(&Runtime::sample_alerts, this, kismet_);
        wireless_worker_ = std::thread(&Runtime::sample_wireless, this);
        publisher_ = std::thread(&Runtime::publish, this);
    } catch (...) {
        {
            const std::lock_guard<std::mutex> guard(lock_);
            stop_ = true;
        }
        wake_.notify_all();
        if (system_worker_.joinable()) system_worker_.join();
        if (wireless_worker_.joinable()) wireless_worker_.join();
        if (alert_worker_.joinable()) alert_worker_.join();
        throw;
    }
}

Runtime::~Runtime() {
    {
        const std::lock_guard<std::mutex> guard(lock_);
        stop_ = true;
    }
    wake_.notify_all();
    system_worker_.join();
    wireless_worker_.join();
    alert_worker_.join();
    {
        const std::lock_guard<std::mutex> guard(lock_);
        inputs_finished_ = true;
    }
    wake_.notify_all();
    publisher_.join();
}

bool Runtime::wait(Clock::duration duration) {
    std::unique_lock<std::mutex> guard(lock_);
    return wake_.wait_for(guard, duration, [this] { return stop_.load(); });
}

v1::MonitoringSnapshot Runtime::snapshot() const {
    const std::lock_guard<std::mutex> guard(snapshot_lock_);
    return snapshot_;
}

bool Runtime::observed_devices(const v1::ObservedDevicesRequest& request, v1::ObservedDevicesPage& response,
                               std::string& error) {
    static const std::regex mac_pattern("([0-9a-f]{2}:){5}[0-9a-f]{2}");
    const auto length = request.has_page_size() ? request.page_size() : 32;
    if (length == 0 || length > 32 || request.ssid_filter().size() > 128 ||
        request.page_token().size() > 32 ||
        (!request.bssid_filter().empty() && !std::regex_match(request.bssid_filter(), mac_pattern))) {
        error = "invalid_device_filter";
        return false;
    }
    const std::lock_guard<std::mutex> guard(lock_);
    if (throttled_) {
        response.set_coverage("resource_fallback");
        return true;
    }
    auto view = view_;
    std::size_t offset = 0;
    auto expires = boottime_ms() + 45000;
    if (!request.page_token().empty()) {
        const auto cursor = cursors_.find(request.page_token());
        if (cursor == cursors_.end() || cursor->second.expires <= boottime_ms()) {
            error = "STALE_PAGE";
            return false;
        }
        const auto& bound = cursor->second;
        if (bound.phone != request.phone_id() || bound.ssid != request.ssid_filter() ||
            bound.bssid != request.bssid_filter() || bound.kind != request.kind()) {
            error = "invalid_page_token";
            return false;
        }
        offset = bound.offset;
        view = bound.view;
        expires = bound.expires;
    }
    if (!view) {
        response.set_coverage("unavailable");
        return true;
    }
    response.set_generation(view->generation);
    response.set_truncated(view->summary.truncated());
    response.set_coverage(view->summary.coverage());
    if (view->summary.has_sampled_at_ms()) response.set_sampled_at_ms(view->summary.sampled_at_ms());
    std::size_t count = 0;
    for (const auto& device : view->devices) {
        if (request.kind() != v1::OBSERVED_KIND_UNSPECIFIED && device.kind() != request.kind()) continue;
        if (!request.ssid_filter().empty() && device.ssid() != request.ssid_filter()) continue;
        if (!request.bssid_filter().empty() && device.bssid() != request.bssid_filter() &&
            device.related_ap_bssid() != request.bssid_filter()) continue;
        if (count >= offset && count - offset < length) *response.add_devices() = device;
        ++count;
    }
    response.set_total_count(count);
    if (count > offset + response.devices_size()) {
        const auto next = random_id();
        if (cursors_.size() >= 128) cursors_.erase(cursors_.begin());
        cursors_.emplace(next, PageCursor{offset + response.devices_size(), request.phone_id(),
                                        request.ssid_filter(), request.bssid_filter(), request.kind(), expires, view});
        response.set_next_page_token(next);
    }
    return true;
}

void Runtime::enqueue(v1::MonitoringEvent event) {
    if (!event.has_occurrences()) event.set_occurrences(1);
    const std::lock_guard<std::mutex> guard(lock_);
    if (event.ByteSizeLong() > EventStore::max_event_bytes) {
        ++drops_;
        return;
    }
    const auto duplicate = std::find_if(pending_.begin(), pending_.end(),
        [&](auto& queued) { return same_notice(queued, event); });
    if (duplicate != pending_.end()) {
        if (duplicate->occurrences() < std::numeric_limits<std::uint32_t>::max()) {
            duplicate->set_occurrences(duplicate->occurrences() + 1);
        }
        ++merges_;
        return;
    }
    if (pending_.size() == kPending) {
        const auto worst = std::max_element(pending_.begin(), pending_.end(),
            [](auto& a, auto& b) { return a.priority() < b.priority(); });
        ++drops_;
        if (event.priority() > worst->priority() ||
            (event.priority() == worst->priority() && event.priority() >= v1::P2)) return;
        pending_.erase(worst);
    }
    pending_.push_back(std::move(event));
    wake_.notify_all();
}

void Runtime::evaluate_pressure(const v1::SystemMetrics& sample) {
    constexpr auto mib = 1024ull * 1024;
    const bool cpu = sample.has_cpu_usage();
    const bool memory = sample.has_memory_available_bytes();
    const bool psi = sample.memory_pressure().has_some_avg10();
    const auto usage = sample.cpu_usage();
    const auto available = sample.memory_available_bytes();
    const auto stall = sample.memory_pressure().some_avg10();
    const std::array<bool, 6> exceeded{cpu && usage >= 80, memory && available < 256*mib, psi && stall >= 10,
                                      cpu && usage >= 95, memory && available < 128*mib, psi && stall >= 20};
    constexpr std::array<unsigned, 6> limits{30, 15, 15, 15, 5, 10};
    constexpr std::array<const char*, 6> reasons{"cpu_utilization", "available_memory", "memory_psi",
                                                "cpu_utilization_critical", "available_memory_critical", "memory_psi_critical"};
    auto next = (cpu || memory || psi) ? v1::NORMAL : v1::RESOURCE_LEVEL_UNSPECIFIED;
    std::string reason;
    for (std::size_t i = 0; i < exceeded.size(); ++i) {
        pressure_ticks_[i] = exceeded[i] ? std::min(pressure_ticks_[i]+1, limits[i]) : 0;
        if (pressure_ticks_[i] == limits[i]) {
            next = i < 3 ? v1::LEVEL1_WARN : v1::LEVEL2_FALLBACK;
            reason = reasons[i];
        }
    }
    const bool below = cpu && memory && (!psi || stall < 8) && usage < 75 && available >= 288*mib;
    recovery_ticks_ = below ? std::min(60u, recovery_ticks_ + 1) : 0;
    if (pressure_level_ == v1::LEVEL2_FALLBACK && recovery_ticks_ < 60) next = v1::LEVEL2_FALLBACK;
    if (next != pressure_level_) {
        const bool high = next == v1::LEVEL1_WARN || next == v1::LEVEL2_FALLBACK;
        if (high || (next == v1::NORMAL && pressure_level_ != v1::RESOURCE_LEVEL_UNSPECIFIED)) {
            enqueue(notice(high ? "resource_pressure" : "resource_recovered",
                           next == v1::LEVEL2_FALLBACK ? v1::P1 : v1::P2, "linux", reason));
        }
        pressure_level_ = next;
    }
    throttled_ = next == v1::LEVEL2_FALLBACK;
    const std::lock_guard<std::mutex> guard(lock_);
    if (!reason.empty() || next != v1::LEVEL2_FALLBACK) pressure_report_.set_reason(reason);
    pressure_report_.set_level(next);
}

void Runtime::sample_system() {
    LinuxCollector linux_metrics;
    while (!stop_) {
        const auto start = Clock::now();
        auto result = linux_metrics.sample();
        evaluate_pressure(result);
        {
            const std::lock_guard<std::mutex> guard(lock_);
            system_ = std::move(result);
        }
        wait(start + 1s - Clock::now());
    }
}

void Runtime::sample_wireless() {
    auto next_fallback = Clock::time_point{};
    while (!stop_) {
        const auto start = Clock::now();
        auto result = kismet_.sample(!throttled_);
        auto policy = capture_policy();
        if (throttled_ && start >= next_fallback && (policy.actual() == "balanced" || policy.actual() == "extended" ||
                                                    policy.requested() == "balanced" || policy.requested() == "extended")) {
            run_control("pressure_light", random_id());
            next_fallback = start + 30s;
        }
        const auto state = result.capture.datasource_state() + "/" + result.capture.coverage() + "/" + result.capture.reason();
        if (state != capture_state_) {
            const bool active = result.capture.has_datasource_running() && result.capture.datasource_running() &&
                                result.capture.coverage() != "unavailable";
            enqueue(notice(active ? "capture_available" : "capture_degraded",
                           active ? v1::P2 : v1::P1, "kismet", state));
            capture_state_ = state;
        }

        const auto& coverage = result.wireless.coverage();
        const auto& source = result.capture.datasource_uuid();
        if (!source.empty() && (coverage == "live_source_window" || coverage == "partial_live_source_window")) {
            std::unordered_set<std::string> current;
            for (const auto& ap : result.wireless.priority_aps()) {
                current.insert(ap.bssid());
                if (priority_source_ != source || priority_aps_.count(ap.bssid())) continue;
                auto event = notice("priority_ap_observed", v1::P3, "kismet", "entered_priority_view");
                event.set_bssid(ap.bssid());
                if (ap.has_last_seen_ms()) event.set_timestamp_ms(ap.last_seen_ms());
                enqueue(std::move(event));
            }
            priority_aps_ = std::move(current);
            priority_source_ = source;
        } else {
            priority_aps_.clear();
            priority_source_.clear();
        }
        {
            const std::lock_guard<std::mutex> guard(lock_);
            const bool active = result.capture.datasource_state() == "ready" &&
                                result.capture.coverage() == "live_monitor_active";
            if (active && (observation_started_ < 0 || observation_epoch_ != result.observation_epoch)) {
                observation_started_ = boottime_ms();
                observation_.set_session_id(random_id());
                observation_.clear_reset_reason();
                observation_epoch_ = result.observation_epoch;
            } else if (!active && observation_started_ >= 0) {
                observation_started_ = -1;
                observation_.set_reset_reason(result.capture.reason());
            }
            observation_.set_active(active);
            if (!active) observation_.clear_continuous_active_ms();
            policy_ = std::move(policy);
            capture_ = std::move(result.capture);
            wireless_ = std::move(result.wireless);
            view_ = std::make_shared<DeviceView>(DeviceView{std::move(result.devices), wireless_, ++generation_});
            const auto now = boottime_ms();
            for (auto cursor = cursors_.begin(); cursor != cursors_.end();) {
                if (cursor->second.expires <= now || !active) cursor = cursors_.erase(cursor);
                else ++cursor;
            }
        }
        wait(start + (throttled_ ? 15s : 5s) - Clock::now());
    }
}

void Runtime::sample_alerts(KismetCollector collector) {
    std::unordered_map<std::string, std::int64_t> seen;
    while (!stop_) {
        const auto start = Clock::now();
        const auto now = wall_ms();
        auto alerts = collector.sample_alerts();
        for (auto it = seen.begin(); it != seen.end();) {
            if (now - it->second > 300000) it = seen.erase(it);
            else ++it;
        }
        for (auto& event : alerts.events) {
            if (seen.count(event.event_id()) || seen.size() >= 4096) continue;
            seen.emplace(event.event_id(), event.timestamp_ms());
            if (outbox_ && (event.risk_class() == v1::HIGH || event.risk_class() == v1::CRITICAL)) {
                outbox_->submit(event);
            } else {
                enqueue(std::move(event));
            }
        }
        {
            const std::lock_guard<std::mutex> guard(lock_);
            alert_health_.set_component_id(v1::ALERT_INPUT);
            alert_health_.set_sampled_at_ms(now);
            alert_health_.set_state(v1::DEGRADED);
            alert_health_.set_reason(alerts.reachable ? "polling_best_effort" : "alert_input_unavailable");
            if (alerts.reachable) alert_health_.set_last_ok_ms(now);
        }
        wait(start + 3s - Clock::now());
    }
}

void Runtime::publish() {
    auto next_snapshot = Clock::now();
    auto next_memory_report = Clock::now() + 60s;
    std::uint64_t sequence = 0;
    for (;;) {
        std::vector<v1::MonitoringEvent> batch;
        v1::MonitoringSnapshot message;
        {
            std::unique_lock<std::mutex> guard(lock_);
            wake_.wait_until(guard, next_snapshot, [this] { return inputs_finished_ || !pending_.empty(); });
            if (inputs_finished_ && pending_.empty()) return;
            if (Clock::now() >= next_snapshot) {
                next_snapshot = Clock::now() + 3s;
                message.set_boot_id(boot_id_);
                message.set_sequence(++sequence);
                message.set_timestamp_ms(wall_ms());
                message.set_schema_version(1);
                *message.mutable_system() = system_;
                *message.mutable_capture() = capture_;
                *message.mutable_wireless() = wireless_;
                message.set_capability_version(2);
                message.set_device_boot_id(device_boot_id_);
                for (const char* name : {"device_pages", "capture_profiles", "device_recovery", "highrisk_ack"}) {
                    message.add_supported_features(name);
                }
                *message.mutable_capture_policy() = policy_;
                *message.mutable_resource_pressure() = pressure_report_;
                *message.mutable_observation_session() = observation_;
                if (observation_started_ >= 0) {
                    message.mutable_observation_session()->set_continuous_active_ms(boottime_ms() - observation_started_);
                }
                *message.mutable_device_health()->add_components() = alert_health_;
                auto* delivery = message.mutable_delivery();
                delivery->set_dropped_events(drops_);
                delivery->set_merged_events(merges_);
                delivery->set_pending_events(static_cast<unsigned>(pending_.size()));
            }
            batch.assign(std::make_move_iterator(pending_.begin()), std::make_move_iterator(pending_.end()));
            pending_.clear();
        }
        events_.append(batch);
        if (message.has_sequence()) {
            if (outbox_) *message.mutable_high_risk_delivery() = outbox_->status();
            add_component_health(message);
            message.set_latest_event_sequence(events_.latest());
            auto* delivery = message.mutable_delivery();
            delivery->set_dropped_events(delivery->dropped_events() + events_.stats().dropped);
            const std::lock_guard<std::mutex> guard(snapshot_lock_);
            snapshot_ = std::move(message);
        }
        if (Clock::now() >= next_memory_report) {
            const auto stats = events_.stats();
            std::clog << "RAM usage: telemetry_rss_bytes=" << resident_set_bytes()
                      << " event_buffer_count=" << stats.count
                      << " event_buffer_event_limit=" << stats.event_limit
                      << " event_buffer_serialized_bytes=" << stats.serialized_bytes
                      << " event_buffer_serialized_byte_limit=" << stats.serialized_byte_limit
                      << " event_buffer_dropped=" << stats.dropped << '\n';
            next_memory_report = Clock::now() + 60s;
        }
    }
}

}  // namespace pocketnet::telemetry
