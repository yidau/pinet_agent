#pragma once

#include <array>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <map>
#include <optional>
#include <string>
#include <vector>

#include "monitoring.pb.h"

namespace pocketnet::telemetry {

class LinuxCollector {
public:
    LinuxCollector(std::filesystem::path proc = "/proc", std::filesystem::path sys = "/sys");
    v1::SystemMetrics sample(std::chrono::steady_clock::time_point now = std::chrono::steady_clock::now());

private:
    std::filesystem::path proc_;
    std::filesystem::path sys_;
    std::optional<std::array<uint64_t, 8>> previous_cpu_;
    std::map<std::string, std::array<uint64_t, 5>> previous_disks_;
    std::chrono::steady_clock::time_point previous_time_{};
};

struct KismetSample {
    v1::CaptureMetrics capture;
    v1::WirelessSummary wireless;
    std::vector<v1::ObservedDevice> devices;
    std::map<std::string, uint64_t> ap_data_bytes;
    std::string observation_epoch;
    std::string capture_profile;
    std::optional<uint64_t> kismet_started;
};

struct KismetAlerts {
    bool reachable = false;
    std::vector<v1::MonitoringEvent> events;
};

class KismetCollector {
public:
    KismetCollector(std::string url, std::string api_key,
                    std::filesystem::path monitor = "/run/piagent-wireless/monitor.json");
    KismetSample sample(bool include_devices = true);
    KismetAlerts sample_alerts() const;

private:
    std::string url_;
    std::string api_key_;
    std::filesystem::path monitor_;
    std::string previous_uuid_;
    std::optional<uint64_t> previous_packets_;
    std::chrono::steady_clock::time_point previous_time_{};
};

}  // namespace pocketnet::telemetry
