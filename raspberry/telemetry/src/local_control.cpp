#include "local_control.hpp"

#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <ifaddrs.h>

#include <algorithm>
#include <array>
#include <filesystem>
#include <fstream>
#include <memory>

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

Json local_request(const Json& input, timeval deadline) {
    struct Socket {
        int descriptor = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
        ~Socket() { if (descriptor >= 0) close(descriptor); }
    } channel;
    if (channel.descriptor < 0) return {};
    if (setsockopt(channel.descriptor, SOL_SOCKET, SO_RCVTIMEO, &deadline, sizeof(deadline)) != 0 ||
        setsockopt(channel.descriptor, SOL_SOCKET, SO_SNDTIMEO, &deadline, sizeof(deadline)) != 0) return {};
    sockaddr_un target{};
    target.sun_family = AF_UNIX;
    constexpr char path[] = "/run/pocketnet-control/control.sock";
    std::copy(std::begin(path), std::end(path), target.sun_path);
    if (connect(channel.descriptor, reinterpret_cast<const sockaddr*>(&target), sizeof(target)) != 0) return {};
    const auto request = input.dump() + "\n";
    if (send(channel.descriptor, request.data(), request.size(), MSG_NOSIGNAL) !=
        static_cast<ssize_t>(request.size())) return {};
    std::string reply;
    while (reply.size() < 1024) {
        std::array<char, 256> bytes{};
        const auto count = recv(channel.descriptor, bytes.data(), bytes.size(), 0);
        if (count <= 0) break;
        reply.append(bytes.data(), count);
        if (reply.find('\n') != std::string::npos) break;
    }
    return Json::parse(reply, nullptr, false);
}

v1::ComponentState component_state(const Json& units, const char* first, const char* second,
                                   bool interface_ready, v1::ComponentState ready) {
    const auto a = text(units, first);
    const auto b = text(units, second);
    if (a == "failed" || b == "failed") return v1::FAILED;
    if (a.empty() || b.empty() || a == "unknown" || b == "unknown") return v1::UNKNOWN;
    if (a == "activating" || b == "activating") return v1::STARTING;
    return a == "active" && b == "active" && interface_ready ? ready : v1::DEGRADED;
}
}  // namespace

v1::ControlCommandResponse run_control(const char* action, const std::string& request_id) {
    v1::ControlCommandResponse result;
    result.set_request_id(request_id);
    result.set_status(v1::REFUSED);
    result.set_accepted(false);
    result.set_reason("local_control_unavailable");
    const auto doc = local_request({{"action", action}, {"request_id", request_id}}, {2, 0});
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


v1::RadioLabStatus run_radio_lab(const v1::RadioLabRequest& request, const v1::ObservedDevice* observed) {
    v1::RadioLabStatus result;
    result.set_accepted(false);
    result.set_phase("unavailable");
    result.set_reason("radio_lab_service_unavailable");
    Json body = {{"action", request.action()}, {"phone_id", request.phone_id()},
                 {"request_id", request.request_id()}, {"profile_id", request.profile_id()},
                 {"session_id", request.session_id()}, {"kind", request.kind()}};
    if (observed) {
        body["observed"] = {{"bssid", observed->bssid()}, {"ssid", observed->ssid()},
                            {"channel", observed->channel()}, {"last_seen_ms", observed->last_seen_ms()}};
    }
    struct Socket {
        int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
        ~Socket() { if (fd >= 0) close(fd); }
    } channel;
    if (channel.fd < 0) return result;
    const timeval timeout{2, 0};
    setsockopt(channel.fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(channel.fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    constexpr char path[] = "/run/piagent-radio/lab.sock";
    std::copy(std::begin(path), std::end(path), addr.sun_path);
    if (connect(channel.fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) return result;
    const auto payload = body.dump() + "\n";
    if (payload.size() > 4000 ||
        send(channel.fd, payload.data(), payload.size(), MSG_NOSIGNAL) != static_cast<ssize_t>(payload.size())) {
        return result;
    }
    std::array<char, 4096> bytes{};
    const auto received = recv(channel.fd, bytes.data(), bytes.size(), 0);
    if (received <= 0 || received >= static_cast<ssize_t>(bytes.size())) return result;
    const auto reply = Json::parse(bytes.data(), bytes.data() + received, nullptr, false);
    if (!reply.is_object()) return result;
    const auto accepted = reply.find("accepted");
    if (accepted != reply.end() && accepted->is_boolean()) result.set_accepted(accepted->get<bool>());
    result.set_phase(text(reply, "phase"));
    result.set_reason(text(reply, "reason"));
    result.set_session_id(text(reply, "session_id"));
    result.set_profile_id(text(reply, "profile_id"));
    result.set_ssid(text(reply, "ssid"));
    result.set_bssid(text(reply, "bssid"));
    result.set_simulated_bssid(text(reply, "simulated_bssid"));
    result.set_channel(text(reply, "channel"));
    result.set_kind(text(reply, "kind"));
    for (const char* key : {"started_at_ms", "finished_at_ms"}) {
        const auto it = reply.find(key);
        if (it != reply.end() && it->is_number_integer() && it->get<std::int64_t>() >= 0) {
            if (std::string(key) == "started_at_ms") result.set_started_at_ms(it->get<std::int64_t>());
            else result.set_finished_at_ms(it->get<std::int64_t>());
        }
    }
    const auto restored = reply.find("kismet_restored");
    if (restored != reply.end() && restored->is_boolean()) result.set_kismet_restored(restored->get<bool>());
    const auto running = reply.find("executor_running");
    if (running != reply.end() && running->is_boolean()) result.set_executor_running(running->get<bool>());
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
    const auto response = local_request({{"action", "health"}}, {1, 0});
    const auto units = text(response, "status") == "ok" ? response.value("units", Json{}) : Json{};
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
    const auto mgmt = component_state(units, "piagent-hotspot.service", "piagent-dhcp.service", mgmt_ip(), v1::READY);
    component(v1::MGMT_WIFI, mgmt,
              mgmt == v1::READY ? "" : (mgmt == v1::UNKNOWN ? "service_status_unavailable" : "hotspot_or_dhcp_not_verified"));
    const auto& capture = snapshot.capture();
    const auto& role = capture.datasource_state();
    component(v1::MONITOR_WIFI, role == "ready" && capture.coverage() == "live_monitor_active" ? v1::READY :
              (role == "paused" ? v1::IDLE : role == "starting" ? v1::STARTING : v1::DEGRADED), capture.reason());
    std::error_code error;
    bool adapter = false;
    for (std::filesystem::directory_iterator it("/sys/class/bluetooth", error), end;
         !error && it != end; it.increment(error)) {
        if (it->path().filename().string().find("hci") == 0) adapter = true;
    }
    const auto ble = component_state(units, "bluetooth.service", "piagent-ble-time-sync.service", adapter, v1::IDLE);
    component(v1::BLE, ble,
              ble == v1::IDLE ? "" : (ble == v1::UNKNOWN ? "service_status_unavailable" : "bluetooth_or_gatt_not_verified"));
}

}  // namespace pocketnet::telemetry
