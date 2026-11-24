#pragma once

#include "collectors.hpp"

#include <deque>
#include <tuple>

namespace pocketnet::telemetry {

class WirelessTraffic {
public:
    using Clock = std::chrono::steady_clock;
    using SsidSummaries = std::map<std::string, v1::ObservedTraffic>;

    SsidSummaries update(KismetSample& sample, const v1::CapturePolicyStatus& policy,
                         Clock::time_point now);

private:
    struct Reading {
        Clock::time_point time;
        uint64_t bytes;
    };
    struct AccessPointHistory {
        std::string ssid;
        int64_t first_seen_ms = 0;
        std::deque<Reading> readings;
    };

    v1::ObservedTraffic observe(const v1::ObservedDevice& ap, uint64_t bytes, Clock::time_point now);

    std::tuple<std::string, std::string, std::string, std::optional<uint64_t>> session_;
    std::optional<Clock::time_point> previous_;
    std::optional<Clock::time_point> partial_;
    std::map<std::string, AccessPointHistory> history_;
};

}  // namespace pocketnet::telemetry
