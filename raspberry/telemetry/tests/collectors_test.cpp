#include "collectors.hpp"

#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>

#include <array>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>

#include <nlohmann/json.hpp>

namespace {

namespace fs = std::filesystem;
using Json = nlohmann::json;
using pocketnet::telemetry::KismetCollector;
using pocketnet::telemetry::LinuxCollector;

void expect(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

class Fixture {
public:
    Fixture() {
        char pattern[] = "/tmp/piagent-collector-test-XXXXXX";
        auto directory = mkdtemp(pattern);
        if (!directory) throw std::runtime_error("cannot create test directory");
        path = directory;
    }

    ~Fixture() {
        std::error_code error;
        fs::remove_all(path, error);
    }

    void write(const fs::path& relative, const std::string& value) {
        const auto file = path / relative;
        fs::create_directories(file.parent_path());
        std::ofstream output(file);
        output << value;
        expect(static_cast<bool>(output), "cannot write fixture");
    }

    fs::path path;
};

void linuxSample() {
    Fixture f;
    f.write("proc/stat", "cpu 100 0 50 400 10 0 0 0 25 4\n");
    f.write("proc/meminfo", "MemTotal: 8000 kB\nMemFree: 1024 kB\nMemAvailable: 6000 kB\n"
                           "SwapTotal: 200 kB\nSwapFree: 0 kB\n");
    f.write("proc/pressure/cpu", "some avg10=7.25 avg60=9.00 avg300=1.00 total=10\nfull avg10=0 avg60=0 total=0\n");
    f.write("proc/pressure/memory", "full avg10=1.5 avg60=0 total=300\n");
    f.write("sys/class/thermal/thermal_zone0/type", "gpu\n");
    f.write("sys/class/thermal/thermal_zone0/temp", "90000\n");
    f.write("sys/class/thermal/thermal_zone7/type", "cpu-thermal\n");
    f.write("sys/class/thermal/thermal_zone7/temp", "48200\n");
    f.write("sys/devices/system/cpu/cpufreq/policy2/scaling_cur_freq", "1500000\n");
    fs::create_directories(f.path / "sys/block/mmcblk0");
    fs::create_directories(f.path / "sys/devices/virtual/block/loop0");
    fs::create_directory_symlink(f.path / "sys/devices/virtual/block/loop0", f.path / "sys/block/loop0");
    f.write("proc/diskstats", "179 0 mmcblk0 10 0 100 0 20 0 200 0 0 15 0\n"
                            "179 1 mmcblk0p1 10 0 100 0 20 0 200 0 0 15 0\n"
                            "7 0 loop0 50 0 4000 0 55 0 5000 0 0 100 0\n");

    LinuxCollector collector(f.path / "proc", f.path / "sys");
    const auto time = std::chrono::steady_clock::now();
    const auto first = collector.sample(time);
    expect(!first.has_cpu_usage() && !first.has_disk_reads_per_second(), "first sample has no counter delta");
    expect(first.memory_used_bytes() == 2000 * 1024 && first.memory_available_bytes() == 6000 * 1024,
           "memory usage uses MemAvailable");
    expect(first.has_swap_free_bytes() && first.swap_free_bytes() == 0, "measured zero is present");
    expect(first.temperature_c() > 48 && first.temperature_c() < 49, "select CPU thermal zone by type");
    expect(first.cpu_frequency_mhz() == 1500, "frequency reported in MHz");
    expect(first.cpu_pressure().some_avg10() == 7.25F && !first.cpu_pressure().has_full_avg10(),
           "system CPU full PSI is undefined");
    expect(first.memory_pressure().has_full_avg60() && first.memory_pressure().full_avg60() == 0
               && !first.has_io_pressure(), "unavailable PSI differs from measured zero");

    f.write("proc/stat", "cpu 130 0 60 460 10 0 0 0 400 99\n");
    f.write("proc/diskstats", "179 0 mmcblk0 14 0 112 0 22 0 206 0 0 45 0\n"
                            "179 1 mmcblk0p1 14 0 112 0 22 0 206 0 0 45 0\n"
                            "7 0 loop0 80 0 8000 0 90 0 10000 0 0 200 0\n");
    const auto second = collector.sample(time + std::chrono::seconds(2));
    expect(second.cpu_usage() > 39.99F && second.cpu_usage() < 40.01F, "CPU delta excludes guest double counting");
    expect(second.disk_read_bytes_per_second() == 3072 && second.disk_write_bytes_per_second() == 1536
               && second.disk_reads_per_second() == 2 && second.disk_writes_per_second() == 1
               && second.disk_busy_ms_per_second() == 15, "disk rates exclude partition and loop duplicates");

    f.write("proc/stat", "cpu 10 0 5 99 0 0 0 0\n");
    f.write("proc/diskstats", "179 0 mmcblk0 1 0 2 0 1 0 2 0 0 2 0\n");
    const auto reset = collector.sample(time + std::chrono::seconds(4));
    expect(!reset.has_cpu_usage() && !reset.has_disk_read_bytes_per_second(), "counter reset yields unavailable");
}

class LocalApi {
public:
    explicit LocalApi(std::map<std::string, Json> responses) : responses_(std::move(responses)) {
        listener_ = socket(AF_INET, SOCK_STREAM, 0);
        if (listener_ < 0) throw std::runtime_error("cannot open loopback fixture socket");
        sockaddr_in addr{};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        socklen_t length = sizeof(addr);
        if (bind(listener_, reinterpret_cast<sockaddr*>(&addr), length) < 0 || listen(listener_, 4) < 0
            || getsockname(listener_, reinterpret_cast<sockaddr*>(&addr), &length) < 0) {
            close(listener_);
            throw std::runtime_error("cannot listen on loopback fixture socket");
        }
        url = "http://127.0.0.1:" + std::to_string(ntohs(addr.sin_port));
        worker_ = std::thread([this] {
            for (int connection; (connection = accept(listener_, nullptr, nullptr)) >= 0;) {
                handle(connection);
                close(connection);
            }
        });
    }

    ~LocalApi() {
        shutdown(listener_, SHUT_RDWR);
        close(listener_);
        worker_.join();
    }

    std::string url;

private:
    void handle(int fd) {
        struct timeval timeout{1, 0};
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        std::string request;
        std::array<char, 4096> chunk{};
        while (request.size() < 64 * 1024) {
            auto bytes = recv(fd, chunk.data(), chunk.size(), 0);
            if (bytes <= 0) return;
            request.append(chunk.data(), static_cast<size_t>(bytes));
            const auto end = request.find("\r\n\r\n");
            if (end == std::string::npos) continue;
            const auto header = request.find("Content-Length: ");
            const auto bodyLength = header == std::string::npos ? 0 : std::strtoul(request.c_str() + header + 16, nullptr, 10);
            if (request.size() < end + 4 + bodyLength) continue;
            break;
        }
        std::istringstream line(request);
        std::string method, path;
        line >> method >> path;
        auto matched = responses_.find(path);
        const bool approved = request.find("Cookie: KISMET=fixture-read-only") != std::string::npos;
        const bool found = matched != responses_.end();
        const auto status = !approved ? "401 Unauthorized" : (found ? "200 OK" : "404 Not Found");
        const auto body = approved && found ? matched->second.dump() : "{}";
        const auto wire = std::string("HTTP/1.1 ") + status + "\r\nContent-Length: "
                        + std::to_string(body.size()) + "\r\nConnection: close\r\n\r\n" + body;
        for (size_t offset = 0; offset < wire.size();) {
            auto sent = send(fd, wire.data() + offset, wire.size() - offset, MSG_NOSIGNAL);
            if (sent <= 0) break;
            offset += static_cast<size_t>(sent);
        }
    }

    int listener_ = -1;
    std::thread worker_;
    std::map<std::string, Json> responses_;
};

void kismetSample() {
    Fixture f;
    constexpr auto source = "3fd447ed-da27-446f-8e92-d35aa1abbf0f";
    constexpr auto uppercase = "3FD447ED-DA27-446F-8E92-D35AA1ABBF0F";
    const auto now = std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
    auto monitor = Json{{"state", "ready"}, {"reason", "ok"}, {"datasource_uuid", source}, {"timestamp_ms", now * 1000}};
    f.write("monitor.json", monitor.dump());
    Json device = {
        {"kismet.device.base.type", "Wi-Fi AP"}, {"kismet.device.base.phyname", "IEEE802.11"},
        {"kismet.device.base.macaddr", "20:00:00:00:00:01"}, {"kismet.device.base.channel", "11"},
        {"kismet.device.base.frequency", 2462000}, {"kismet.device.base.first_time", now - 60},
        {"kismet.device.base.last_time", now - 1}, {"ssid", "Test AP"}, {"beacon_security", "WPA3"},
        {"signal_type", "dbm"}, {"signal_value", -38},
        {"kismet.device.base.seenby", {{"1", {{"kismet.common.seenby.uuid", uppercase}}}}},
    };
    auto mixed = device;
    mixed["kismet.device.base.macaddr"] = "20:00:00:00:00:02";
    mixed["kismet.device.base.seenby"]["2"] = {{"kismet.common.seenby.uuid", "11111111-2222-3333-4444-555555555555"}};
    auto station = device;
    station["kismet.device.base.type"] = "Wi-Fi Client";
    station["kismet.device.base.macaddr"] = "20:00:00:00:00:03";
    station["kismet.device.base.key"] = "client-id";
    station["last_bssid"] = device["kismet.device.base.macaddr"];
    device["associated_clients"] = {{"20:00:00:00:00:03", "client-id"}};
    auto stale = device;
    stale["kismet.device.base.macaddr"] = "20:00:00:00:00:04";
    stale["kismet.device.base.last_time"] = now - 301;
    Json alert = {{"kismet.alert.timestamp", now - 20}, {"kismet.alert.hash", 42}, {"kismet.alert.severity", 20},
                  {"kismet.alert.header", "BEACON_CHANGE"}, {"kismet.alert.text", "A test alert"},
                  {"kismet.alert.bssid", device["kismet.device.base.macaddr"]}};
    Json unrelated = alert;
    unrelated["kismet.alert.header"] = "DEAUTHFLOOD";
    unrelated["kismet.alert.bssid"] = mixed["kismet.device.base.macaddr"];
    const auto choices = Json::array({{
        {"kismet.datasource.uuid", uppercase},
        {"kismet.datasource.type_driver", {{"kismet.datasource.driver.type", "linuxwifi"}}},
        {"kismet.datasource.running", true}, {"kismet.datasource.paused", false},
        {"kismet.datasource.error", false}, {"kismet.datasource.channel", "11"},
    }});
    std::vector<uint64_t> seconds(60, 0);
    seconds[now % 60] = 17;
    const auto stats = Json{{"kismet.packetchain.queued_packets_rrd", {
        {"kismet.common.rrd.last_time", now}, {"kismet.common.rrd.serial_time", now},
        {"kismet.common.rrd.minute_vec", seconds},
    }}};
    LocalApi fake({
        {"/system/status.json", {{"kismet.system.version", "fixture"}}},
        {"/datasource/all_sources.json", choices},
        {"/packetchain/packet_stats.json", stats},
        {std::string("/devices/views/seenby-") + uppercase + "/devices.json",
            {{"data", Json::array({device, mixed, station, stale})}, {"recordsFiltered", 4}}},
        {"/alerts/all_alerts.json", Json::array({alert, unrelated})},
    });
    KismetCollector collector(fake.url, "fixture-read-only", f.path / "monitor.json");
    const auto reading = collector.sample();
    expect(reading.capture.kismet_running() && reading.capture.datasource_running() && reading.capture.backlog() == 17,
           "read only the selected Kismet datasource and current backlog");
    expect(!reading.capture.has_dropped_packets() && !reading.capture.has_processed_packets_per_second(),
           "unsupported packet counters remain unavailable");
    expect(reading.wireless.ap_count() == 1 && reading.wireless.client_count() == 1 && reading.wireless.truncated(),
           "count deduplicated live metadata without mixed or stale readings");
    expect(reading.wireless.priority_aps_size() == 1 && reading.wireless.priority_aps(0).frequency_khz() == 2462000,
           "priority AP holds lightweight measured metadata");
    expect(reading.devices.size() == 2 &&
           reading.devices[1].association_state() == pocketnet::v1::CONFIRMED,
           "explicit Kismet evidence relates the client to the observed AP");
    const auto alerts = collector.sample_alerts();
    expect(alerts.reachable && alerts.events.size() == 2 &&
           alerts.events[0].risk_class() == pocketnet::v1::SUSPICIOUS &&
           alerts.events[1].risk_class() == pocketnet::v1::CRITICAL &&
           alerts.events[1].confidence() == pocketnet::v1::LIMITED &&
           alerts.events[0].event_id() != alerts.events[1].event_id(),
           "alerts are independent of the view and ignore an upstream hash collision");
    monitor["timestamp_ms"] = (now - 60) * 1000;
    f.write("monitor.json", monitor.dump());
    const auto expired = collector.sample();
    expect(expired.capture.datasource_state() == "degraded" && !expired.wireless.has_ap_count(),
           "stale manager state yields degraded rather than a quiet AP count");
}

}  // namespace

int main() {
    try {
        linuxSample();
        kismetSample();
        std::cout << "Collectors fixture checks passed\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return EXIT_FAILURE;
    }
}
