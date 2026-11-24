#include "wireless_traffic.hpp"

#include <limits>

namespace pocketnet::telemetry {
namespace {

using namespace std::chrono_literals;
constexpr auto kWindow = 30s;
constexpr auto kMaxSampleGap = 10s;
constexpr size_t kHistoryLimit = 16;

struct SsidTotals {
    size_t bssids = 0;
    size_t measured = 0;
    uint64_t bytes = 0;
    bool waiting = false;
    bool estimated = false;
    bool overflow = false;
};

}  // namespace

v1::ObservedTraffic WirelessTraffic::observe(const v1::ObservedDevice& ap, uint64_t bytes,
                                             Clock::time_point now) {
    auto& history = history_[ap.bssid()];
    auto& readings = history.readings;
    if (!readings.empty() &&
        (history.ssid != ap.ssid() || history.first_seen_ms != ap.first_seen_ms() ||
         bytes < readings.back().bytes)) {
        readings.clear();
    }
    history.ssid = ap.ssid();
    history.first_seen_ms = ap.first_seen_ms();
    readings.push_back({now, bytes});
    const auto cutoff = now - kWindow;
    while (readings.size() > 1 && (readings[1].time <= cutoff || readings.size() > kHistoryLimit)) {
        readings.pop_front();
    }

    v1::ObservedTraffic traffic;
    if (readings.front().time > cutoff) {
        traffic.set_status(v1::TRAFFIC_WARMING_UP);
        return traffic;
    }

    auto observed = bytes - readings.front().bytes;
    if (readings.front().time < cutoff) {
        const auto& first = readings.front();
        const auto& next = readings[1];
        const auto interval = next.bytes - first.bytes;
        const uint64_t span = std::chrono::duration_cast<std::chrono::milliseconds>(next.time - first.time).count();
        const uint64_t before = std::chrono::duration_cast<std::chrono::milliseconds>(cutoff - first.time).count();
        // Only the boundary interval needs interpolation. Split the product to avoid overflow.
        observed -= (interval / span) * before + (interval % span) * before / span;
        traffic.set_estimated(interval != 0);
    }
    traffic.set_status(v1::TRAFFIC_OBSERVED);
    traffic.set_observed_bytes(observed);
    traffic.set_window_ms(std::chrono::duration_cast<std::chrono::milliseconds>(kWindow).count());
    return traffic;
}

WirelessTraffic::SsidSummaries WirelessTraffic::update(KismetSample& sample,
                                                        const v1::CapturePolicyStatus& policy,
                                                        Clock::time_point now) {
    now = std::chrono::time_point_cast<std::chrono::milliseconds>(now);
    const auto& profile = sample.capture_profile;
    const bool ready = sample.capture.coverage() == "live_monitor_active" &&
        sample.wireless.has_sampled_at_ms() && !sample.observation_epoch.empty() &&
        policy.phase() != "switching" && policy.actual() == profile;
    const bool enabled = ready && (profile == "balanced" || profile == "extended");
    const auto empty_status = ready && profile == "light"
        ? v1::TRAFFIC_PROFILE_FILTERED : v1::TRAFFIC_UNAVAILABLE;
    auto session = std::make_tuple(sample.capture.datasource_uuid(), sample.observation_epoch,
                                   profile, sample.kismet_started);
    if (!enabled || session != session_ || !previous_ || now <= *previous_ || now - *previous_ > kMaxSampleGap) {
        history_.clear();
        partial_.reset();
    }
    session_ = std::move(session);
    if (enabled) {
        previous_ = now;
        if (sample.wireless.truncated()) partial_ = now;
        for (auto it = history_.begin(); it != history_.end();) {
            if (sample.ap_data_bytes.count(it->first)) ++it;
            else it = history_.erase(it);
        }
    } else {
        previous_.reset();
    }

    std::map<std::string, SsidTotals> totals;
    for (auto& ap : sample.devices) {
        if (ap.kind() != v1::AP) continue;
        v1::ObservedTraffic traffic;
        const auto bytes = sample.ap_data_bytes.find(ap.bssid());
        if (enabled && bytes != sample.ap_data_bytes.end()) traffic = observe(ap, bytes->second, now);
        else traffic.set_status(empty_status);
        if (!ap.ssid().empty()) {
            auto& total = totals[ap.ssid()];
            ++total.bssids;
            total.waiting |= traffic.status() == v1::TRAFFIC_WARMING_UP;
            if (traffic.has_observed_bytes()) {
                ++total.measured;
                const auto room = std::numeric_limits<uint64_t>::max() - total.bytes;
                const auto count = traffic.observed_bytes();
                total.overflow |= count > room;
                total.bytes += count > room ? room : count;
                total.estimated |= traffic.estimated();
            }
        }
        *ap.mutable_traffic() = std::move(traffic);
    }

    SsidSummaries summaries;
    for (const auto& [ssid, total] : totals) {
        auto& traffic = summaries[ssid];
        if (total.measured == 0) {
            traffic.set_status(total.waiting ? v1::TRAFFIC_WARMING_UP : empty_status);
            continue;
        }
        const bool partial = total.measured != total.bssids || total.overflow ||
            (partial_ && now - *partial_ < kWindow);
        traffic.set_status(partial ? v1::TRAFFIC_PARTIAL : v1::TRAFFIC_OBSERVED);
        traffic.set_observed_bytes(total.bytes);
        traffic.set_window_ms(std::chrono::duration_cast<std::chrono::milliseconds>(kWindow).count());
        traffic.set_estimated(total.estimated);
    }
    return summaries;
}

}  // namespace pocketnet::telemetry
