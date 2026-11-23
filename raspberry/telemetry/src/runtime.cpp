#include "runtime.hpp"

#include <google/protobuf/util/json_util.h>
#include <sys/stat.h>

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <utility>

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
    return event;
}

bool same_notice(const v1::MonitoringEvent& lhs, const v1::MonitoringEvent& rhs) {
    if (!lhs.evidence_id().empty() || !rhs.evidence_id().empty()) {
        return !lhs.evidence_id().empty() && lhs.source() == rhs.source() &&
               lhs.evidence_id() == rhs.evidence_id();
    }
    return lhs.event_type() == rhs.event_type() && lhs.source() == rhs.source() &&
           lhs.bssid() == rhs.bssid() && lhs.description() == rhs.description();
}

void write_system_cache(const std::string& path, const v1::SystemMetrics& metrics) {
    std::string json;
    google::protobuf::util::JsonPrintOptions options;
    options.preserve_proto_field_names = true;
    if (!google::protobuf::util::MessageToJsonString(metrics, &json, options).ok()) {
        throw std::runtime_error("Unable to serialize system snapshot");
    }
    const auto temporary = path + ".tmp";
    {
        std::ofstream file(temporary, std::ios::trunc);
        file << json;
        file.close();
        if (!file) throw std::runtime_error("Unable to write system snapshot");
    }
    if (chmod(temporary.c_str(), 0644) != 0) throw std::runtime_error("Unable to share system snapshot");
    std::filesystem::rename(temporary, path);
}
}  // namespace

std::int64_t wall_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

Runtime::Runtime(EventStore& events, KismetCollector kismet, std::string boot_id, std::string system_cache)
    : events_(events), kismet_(std::move(kismet)), boot_id_(std::move(boot_id)),
      system_cache_(std::move(system_cache)) {
    capture_.set_datasource_state("starting");
    capture_.set_coverage("unavailable");
    snapshot_.set_boot_id(boot_id_);
    snapshot_.set_schema_version(1);
    snapshot_.set_timestamp_ms(wall_ms());
    snapshot_.set_latest_event_sequence(events_.latest());
    *snapshot_.mutable_capture() = capture_;
    try {
        system_worker_ = std::thread(&Runtime::sample_system, this);
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

void Runtime::enqueue(v1::MonitoringEvent event) {
    event.set_boot_id(boot_id_);
    if (!event.has_occurrences()) event.set_occurrences(1);
    const std::lock_guard<std::mutex> guard(lock_);
    const auto duplicate = std::find_if(pending_.begin(), pending_.end(),
        [&](auto& queued) { return same_notice(queued, event); });
    if (duplicate != pending_.end()) {
        duplicate->set_occurrences(duplicate->occurrences() + 1);
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

void Runtime::detect_pressure(PressureState& state, const v1::Pressure& pressure) {
    if (!pressure.has_some_avg10()) {
        state.ticks = 0;
        return;
    }
    float value = pressure.some_avg10();
    const bool changed = state.high ? value < state.limit * 0.7f : value >= state.limit;
    state.ticks = changed ? state.ticks + 1 : 0;
    if (state.ticks < 3) return;
    state.high = !state.high;
    state.ticks = 0;
    enqueue(notice(state.high ? "resource_pressure" : "resource_recovered",
                   state.high && std::string(state.name) == "memory" ? v1::P1 : v1::P2, "linux",
                   std::string(state.name) + (state.high ? "_psi_high" : "_psi_recovered")));
}

void Runtime::sample_system() {
    LinuxCollector linux_metrics;
    while (!stop_) {
        const auto start = Clock::now();
        auto result = linux_metrics.sample();
        detect_pressure(pressures_[0], result.cpu_pressure());
        detect_pressure(pressures_[1], result.memory_pressure());
        detect_pressure(pressures_[2], result.io_pressure());
        const bool limit = std::any_of(pressures_.begin(), pressures_.end(),
                                      [](const auto& state) { return state.high; });
        if (throttled_.exchange(limit) != limit) {
            enqueue(notice(limit ? "sampling_degraded" : "sampling_recovered", v1::P2, "telemetry",
                           limit ? "wireless_summary_polling_reduced" : "wireless_summary_polling_restored"));
        }
        {
            const std::lock_guard<std::mutex> guard(lock_);
            system_ = std::move(result);
        }
        wait(start + 1s - Clock::now());
    }
}

void Runtime::sample_wireless() {
    while (!stop_) {
        const auto start = Clock::now();
        auto result = kismet_.sample();
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
        for (auto& event : result.events) enqueue(std::move(event));
        {
            const std::lock_guard<std::mutex> guard(lock_);
            capture_ = std::move(result.capture);
            wireless_ = std::move(result.wireless);
        }
        wait(start + (throttled_ ? 15s : 5s) - Clock::now());
    }
}

void Runtime::publish() {
    auto next_snapshot = Clock::now();
    std::uint64_t sequence = 0;
    bool journal_error = false;
    bool cache_error = false;
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
                auto* delivery = message.mutable_delivery();
                delivery->set_dropped_events(drops_);
                delivery->set_merged_events(merges_);
                delivery->set_pending_events(static_cast<unsigned>(pending_.size()));
            }
            batch.assign(std::make_move_iterator(pending_.begin()), std::make_move_iterator(pending_.end()));
            pending_.clear();
        }
        try {
            events_.append(batch);
            if (journal_error) {
                journal_error = false;
                enqueue(notice("event_storage_recovered", v1::P1, "telemetry", "event_storage_recovered"));
            }
        } catch (const std::exception& error) {
            if (!journal_error) std::cerr << "Telemetry event storage failed: " << error.what() << '\n';
            journal_error = true;
            const std::lock_guard<std::mutex> guard(lock_);
            drops_ += batch.size();
        }
        if (message.has_sequence()) {
            if (!system_cache_.empty() && message.system().has_sampled_at_ms()) {
                try {
                    write_system_cache(system_cache_, message.system());
                    cache_error = false;
                } catch (const std::exception&) {
                    if (!cache_error) std::cerr << "Unable to publish the local system snapshot\n";
                    cache_error = true;
                }
            }
            try {
                message.set_latest_event_sequence(events_.latest());
            } catch (const std::exception&) {
                message.mutable_capture()->set_reason("event_storage_unavailable");
            }
            const std::lock_guard<std::mutex> guard(snapshot_lock_);
            snapshot_ = std::move(message);
        }
    }
}

}  // namespace pocketnet::telemetry
