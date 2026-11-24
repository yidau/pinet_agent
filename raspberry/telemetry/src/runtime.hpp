#pragma once

#include "collectors.hpp"
#include "event_store.hpp"
#include "high_risk_outbox.hpp"

#include <array>
#include <atomic>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <memory>
#include <thread>
#include <unordered_map>
#include <unordered_set>

namespace pocketnet::telemetry {

class Runtime {
public:
    Runtime(EventStore& events, KismetCollector kismet, std::string boot_id,
            std::string device_boot_id = {}, HighRiskOutbox* outbox = nullptr);
    ~Runtime();
    v1::MonitoringSnapshot snapshot() const;
    bool observed_devices(const v1::ObservedDevicesRequest& request, v1::ObservedDevicesPage& response,
                          std::string& error);

private:
    struct DeviceView {
        std::vector<v1::ObservedDevice> devices;
        v1::WirelessSummary summary;
        std::uint64_t generation;
    };
    struct PageCursor {
        std::size_t offset;
        std::string phone, ssid, bssid;
        v1::ObservedDeviceKind kind;
        std::int64_t expires;
        std::shared_ptr<const DeviceView> view;
    };

    void sample_system();
    void sample_wireless();
    void sample_alerts(KismetCollector collector);
    void publish();
    void enqueue(v1::MonitoringEvent event);
    void evaluate_pressure(const v1::SystemMetrics& sample);
    bool wait(std::chrono::steady_clock::duration duration);

    EventStore& events_;
    KismetCollector kismet_;
    const std::string boot_id_;
    const std::string device_boot_id_;
    HighRiskOutbox* const outbox_;
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
    v1::CapturePolicyStatus policy_;
    v1::ObservationSession observation_;
    v1::ResourcePressureStatus pressure_report_;
    v1::ComponentHealth alert_health_;
    std::int64_t observation_started_ = -1;
    std::string observation_epoch_;
    std::shared_ptr<const DeviceView> view_;
    std::uint64_t generation_ = 0;
    std::unordered_map<std::string, PageCursor> cursors_;
    v1::MonitoringSnapshot snapshot_;
    std::string capture_state_;
    std::unordered_set<std::string> priority_aps_;
    std::string priority_source_;
    std::array<unsigned, 6> pressure_ticks_{};
    unsigned recovery_ticks_ = 0;
    v1::ResourceLevel pressure_level_ = v1::RESOURCE_LEVEL_UNSPECIFIED;
    std::thread system_worker_, wireless_worker_, alert_worker_, publisher_;
};

std::int64_t wall_ms();

}  // namespace pocketnet::telemetry
