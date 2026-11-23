#pragma once

#include "collectors.hpp"
#include "event_store.hpp"

#include <array>
#include <atomic>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <thread>
#include <unordered_set>

namespace pocketnet::telemetry {

class Runtime {
public:
    Runtime(EventStore& events, KismetCollector kismet, std::string boot_id);
    ~Runtime();
    v1::MonitoringSnapshot snapshot() const;

private:
    struct PressureState {
        const char* name;
        float limit;
        unsigned ticks = 0;
        bool high = false;
    };

    void sample_system();
    void sample_wireless();
    void publish();
    void enqueue(v1::MonitoringEvent event);
    void detect_pressure(PressureState& state, const v1::Pressure& pressure);
    bool wait(std::chrono::steady_clock::duration duration);

    EventStore& events_;
    KismetCollector kismet_;
    const std::string boot_id_;
    mutable std::mutex lock_;
    mutable std::mutex snapshot_lock_;
    std::condition_variable wake_;
    std::atomic<bool> stop_{false};
    std::atomic<bool> inputs_finished_{false};
    std::atomic<bool> throttled_{false};
    std::deque<v1::MonitoringEvent> pending_;
    std::uint64_t drops_ = 0;
    std::uint64_t merges_ = 0;
    v1::SystemMetrics system_;
    v1::CaptureMetrics capture_;
    v1::WirelessSummary wireless_;
    v1::MonitoringSnapshot snapshot_;
    std::string capture_state_;
    std::unordered_set<std::string> priority_aps_;
    std::string priority_source_;
    std::array<PressureState, 3> pressures_{{{"cpu", 25}, {"memory", 10}, {"io", 20}}};
    std::thread system_worker_, wireless_worker_, publisher_;
};

std::int64_t wall_ms();

}  // namespace pocketnet::telemetry
