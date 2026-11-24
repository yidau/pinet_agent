#include "local_control.hpp"

#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <ifaddrs.h>

#include <algorithm>
#include <array>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <memory>
#include <sstream>

#include <nlohmann/json.hpp>

namespace pocketnet::telemetry {
namespace {
using Json = nlohmann::json;
constexpr const char* control_state = "/run/pocketnet-control/state.json";
constexpr const char* monitor_state = "/run/piagent-wireless/monitor.json";

Json state_file(const char* path) {
    std::ifstream input(path);
    if (!input) return Json::object();
    std::array<char, 4097> content{};
    input.read(content.data(), content.size());
    if (input.gcount() >= 4097) return Json::object();
    auto doc = Json::parse(content.data(), content.data() + input.gcount(), nullptr, false);
    return doc.is_object() ? std::move(doc) : Json::object();
}

std::string text(const Json& node, const char* key) {
    auto found = node.find(key);
    return found != node.end() && found->is_string() && found->get_ref<const std::string&>().size() <= 128
        ? found->get<std::string>() : std::string{};
}

bool mgmt_ip() {
    ifaddrs* addresses = nullptr;
    if (getifaddrs(&addresses) != 0) return false;
    const std::unique_ptr<ifaddrs, decltype(&freeifaddrs)> owner(addresses, freeifaddrs);
    const auto expected = inet_addr("192.168.4.1");
    for (const auto* entry = addresses; entry; entry = entry->ifa_next) {
        if (!entry->ifa_addr || entry->ifa_addr->sa_family != AF_INET || std::string(entry->ifa_name) != "wlan0") continue;
        if (reinterpret_cast<const sockaddr_in*>(entry->ifa_addr)->sin_addr.s_addr == expected) return true;
    }
    return false;
}

std::array<std::string, 4> unit_health() {
    std::array<std::string, 4> result;
    const std::unique_ptr<FILE, decltype(&pclose)> pipe(popen(
        "/usr/bin/timeout 1 /usr/bin/systemctl is-active piagent-hotspot.service piagent-dhcp.service "
        "bluetooth.service piagent-ble-time-sync.service 2>/dev/null", "r"), pclose);
    if (!pipe) return result;
    std::array<char, 32> line{};
    for (auto& state : result) {
        if (!fgets(line.data(), line.size(), pipe.get())) break;
        std::istringstream(line.data()) >> state;
    }
    return result;
}
}  // namespace

v1::ControlCommandResponse run_control(const char* action, const std::string& request_id) {
    v1::ControlCommandResponse result;
    result.set_request_id(request_id);
    result.set_status(v1::REFUSED);
    result.set_accepted(false);
    result.set_reason("local_control_unavailable");
    struct Socket {
        int descriptor = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
        ~Socket() { if (descriptor >= 0) close(descriptor); }
    } channel;
    if (channel.descriptor < 0) return result;
    const timeval deadline{2, 0};
    setsockopt(channel.descriptor, SOL_SOCKET, SO_RCVTIMEO, &deadline, sizeof(deadline));
    setsockopt(channel.descriptor, SOL_SOCKET, SO_SNDTIMEO, &deadline, sizeof(deadline));
    sockaddr_un target{};
    target.sun_family = AF_UNIX;
    constexpr char path[] = "/run/pocketnet-control/control.sock";
    std::copy(std::begin(path), std::end(path), target.sun_path);
    if (connect(channel.descriptor, reinterpret_cast<const sockaddr*>(&target), sizeof(target)) != 0) return result;
    const auto request = Json{{"action", action}, {"request_id", request_id}}.dump() + "\n";
    if (send(channel.descriptor, request.data(), request.size(), MSG_NOSIGNAL) !=
        static_cast<ssize_t>(request.size())) return result;
    std::string reply;
    while (reply.size() < 1024) {
        std::array<char, 256> bytes{};
        const auto count = recv(channel.descriptor, bytes.data(), bytes.size(), 0);
        if (count <= 0) break;
        reply.append(bytes.data(), count);
        if (reply.find('\n') != std::string::npos) break;
    }
    const auto doc = Json::parse(reply, nullptr, false);
    if (!doc.is_object()) return result;
    const auto status = text(doc, "status");
    const auto reason = text(doc, "reason");
    if (status == "accepted") {
        result.set_status(v1::ACCEPTED);
        result.set_accepted(true);
    } else if (status == "busy") {
        result.set_status(v1::BUSY);
    } else if (status == "unsupported") {
        result.set_status(v1::UNSUPPORTED);
    }
    result.set_reason(reason);
    return result;
}

v1::CapturePolicyStatus capture_policy() {
    v1::CapturePolicyStatus result;
    const auto monitor = state_file(monitor_state);
    const auto control = state_file(control_state);
    const auto actual = text(monitor, "actual_profile");
    const auto requested = text(control, "requested");
    const auto phase = text(control, "phase");
    result.set_requested(requested.empty() ? "light" : requested);
    if (text(monitor, "state") == "ready" && !actual.empty() && phase != "switching") result.set_actual(actual);
    if (phase == "switching" || phase == "failed" || phase == "rolled_back") {
        result.set_phase(phase);
        result.set_reason(text(control, "reason"));
    } else {
        result.set_phase(result.has_actual() ? "ready" : "unknown");
        result.set_reason(text(monitor, "reason"));
    }
    const auto forced = control.find("pressure_forced");
    if (forced != control.end() && forced->is_boolean()) result.set_pressure_forced(forced->get<bool>());
    return result;
}

void add_component_health(v1::MonitoringSnapshot& snapshot) {
    const auto control = state_file(control_state);
    const auto units = unit_health();
    const auto component = [&](v1::ComponentId id, v1::ComponentState state, const std::string& reason) {
        auto* health = snapshot.mutable_device_health()->add_components();
        health->set_component_id(id);
        health->set_state(state);
        health->set_reason(reason);
        health->set_sampled_at_ms(snapshot.timestamp_ms());
        if (state == v1::READY || state == v1::IDLE) health->set_last_ok_ms(snapshot.timestamp_ms());
        const auto selected = text(control, "component");
        if ((selected == "monitor" && id == v1::MONITOR_WIFI) ||
            (selected == "hotspot" && id == v1::MGMT_WIFI) || (selected == "ble" && id == v1::BLE)) {
            health->set_recovery_phase(text(control, "recovery_phase"));
            const auto detail = text(control, "reason");
            if (health->recovery_phase() == "failed" && !detail.empty()) health->set_reason(detail);
        }
    };
    const bool mgmt = units[0] == "active" && units[1] == "active" && mgmt_ip();
    component(v1::MGMT_WIFI, mgmt ? v1::READY : (units[0].empty() ? v1::UNKNOWN : v1::DEGRADED),
              mgmt ? "" : "hotspot_or_dhcp_not_verified");
    const auto& capture = snapshot.capture();
    const auto& role = capture.datasource_state();
    component(v1::MONITOR_WIFI, role == "ready" && capture.coverage() == "live_monitor_active" ? v1::READY :
              (role == "starting" ? v1::STARTING : v1::DEGRADED), capture.reason());
    std::error_code error;
    bool adapter = false;
    for (std::filesystem::directory_iterator it("/sys/class/bluetooth", error), end;
         !error && it != end; it.increment(error)) {
        if (it->path().filename().string().find("hci") == 0) adapter = true;
    }
    const bool ble = adapter && units[2] == "active" && units[3] == "active";
    component(v1::BLE, ble ? v1::IDLE : (units[2].empty() ? v1::UNKNOWN : v1::DEGRADED),
              ble ? "" : "bluetooth_or_gatt_not_verified");
}

}  // namespace pocketnet::telemetry
