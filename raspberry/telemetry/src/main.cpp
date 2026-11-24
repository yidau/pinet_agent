#include "event_store.hpp"
#include "device_authorization.hpp"
#include "local_control.hpp"
#include "monitoring.grpc.pb.h"
#include "runtime.hpp"

#include <arpa/inet.h>
#include <grpcpp/grpcpp.h>
#include <grpcpp/resource_quota.h>
#include <pthread.h>
#include <signal.h>

#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <mutex>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <thread>

namespace pocketnet::telemetry {
namespace {
using namespace std::chrono_literals;
using Clock = std::chrono::steady_clock;

std::string env(const char* name, const char* fallback = "") {
    if (const auto* value = std::getenv(name); value && *value) return value;
    return fallback;
}

std::string text_file(const std::filesystem::path& path) {
    std::ifstream input(path);
    if (!input) throw std::runtime_error("Cannot open telemetry input: " + path.string());
    std::ostringstream data;
    data << input.rdbuf();
    return data.str();
}

std::string boot_id() {
    std::string value;
    std::ifstream("/proc/sys/kernel/random/boot_id") >> value;
    if (value.size() != 36) throw std::runtime_error("Linux boot ID unavailable");
    return value;
}

std::string listen_address() {
    const auto value = env("PIAGENT_TELEMETRY_LISTEN", "192.168.4.1:9443");
    const auto split = value.find(':');
    in_addr address{};
    if (split == std::string::npos ||
        inet_pton(AF_INET, value.substr(0, split).c_str(), &address) != 1) {
        throw std::runtime_error("Telemetry requires an explicit IPv4 listen address");
    }
    const auto network = ntohl(address.s_addr);
    const auto first = network >> 24;
    const auto port = value.substr(split + 1);
    if (first == 0 || first >= 224 || port.empty() || port.size() > 5 ||
        port.find_first_not_of("0123456789") != std::string::npos || std::stoul(port) > 65535 ||
        std::stoul(port) == 0) {
        throw std::runtime_error("Invalid telemetry address or port");
    }
    return value;
}

// A stalled transport may block a synchronous write. Retain one bounded message
// and cancel only the affected stream when it cannot make progress.
class DeadlineWriter {
public:
    DeadlineWriter(grpc::ServerContext& context, grpc::ServerWriter<v1::TelemetryMessage>& stream)
        : context_(context), stream_(stream), watcher_(&DeadlineWriter::watch, this) {}

    ~DeadlineWriter() {
        {
            const std::lock_guard<std::mutex> guard(lock_);
            done_ = true;
        }
        changed_.notify_one();
        watcher_.join();
    }

    bool write(const v1::TelemetryMessage& message) {
        {
            const std::lock_guard<std::mutex> guard(lock_);
            deadline_ = Clock::now() + 8s;
        }
        changed_.notify_one();
        const bool written = stream_.Write(message);
        {
            const std::lock_guard<std::mutex> guard(lock_);
            deadline_ = Clock::time_point::max();
        }
        changed_.notify_one();
        return written;
    }

private:
    void watch() {
        std::unique_lock<std::mutex> guard(lock_);
        while (!done_) {
            const auto deadline = deadline_;
            if (deadline == Clock::time_point::max()) {
                changed_.wait(guard);
                continue;
            }
            if (changed_.wait_until(guard, deadline) == std::cv_status::timeout &&
                !done_ && deadline == deadline_) {
                guard.unlock();
                context_.TryCancel();
                return;
            }
        }
    }

    grpc::ServerContext& context_;
    grpc::ServerWriter<v1::TelemetryMessage>& stream_;
    std::mutex lock_;
    std::condition_variable changed_;
    Clock::time_point deadline_ = Clock::time_point::max();
    bool done_ = false;
    std::thread watcher_;
};

class TelemetryService final : public v1::TelemetryService::Service {
public:
    TelemetryService(Runtime& state, const EventStore& events, HighRiskOutbox& outbox, std::string registry)
        : state_(state), events_(events), outbox_(outbox), registry_(std::move(registry)) {}

    grpc::Status AckHighRisk(grpc::ServerContext* context, const v1::AckHighRiskRequest* request,
                             v1::AckHighRiskResponse* response) override {
        auto access = authorize_request(*context, request->phone_id());
        if (!access.ok()) return access;
        if (!hex_id(request->durable_id())) return {grpc::StatusCode::INVALID_ARGUMENT, "Invalid durable ID"};
        if (!owns_session(request->phone_id(), true)) return denied();
        response->set_result(outbox_.acknowledge(request->phone_id(), request->durable_id()));
        return grpc::Status::OK;
    }

    grpc::Status GetObservedDevices(grpc::ServerContext* context, const v1::ObservedDevicesRequest* request,
                                    v1::ObservedDevicesPage* response) override {
        auto access = authorize_request(*context, request->phone_id());
        if (!access.ok()) return access;
        if (!owns_session(request->phone_id())) return denied();
        std::string error;
        if (!state_.observed_devices(*request, *response, error)) {
            return {error == "STALE_PAGE" ? grpc::StatusCode::FAILED_PRECONDITION : grpc::StatusCode::INVALID_ARGUMENT,
                    error};
        }
        return grpc::Status::OK;
    }

    grpc::Status SetCaptureProfile(grpc::ServerContext* context, const v1::SetCaptureProfileRequest* request,
                                    v1::ControlCommandResponse* response) override {
        auto access = control_access(*context, request->phone_id(), request->request_id());
        if (!access.ok()) return access;
        const char* action = nullptr;
        switch (request->target_profile()) {
            case v1::LIGHT: action = "light"; break;
            case v1::BALANCED: action = "balanced"; break;
            case v1::EXTENDED: action = "extended"; break;
            default: return {grpc::StatusCode::INVALID_ARGUMENT, "Unknown capture profile"};
        }
        if (request->target_profile() != v1::LIGHT &&
            state_.snapshot().resource_pressure().level() == v1::LEVEL2_FALLBACK) {
            response->set_request_id(request->request_id());
            response->set_status(v1::REFUSED);
            response->set_reason("resource_level2_fallback");
        } else {
            *response = run_control(action, request->request_id());
        }
        return grpc::Status::OK;
    }

    grpc::Status SetObservationMode(grpc::ServerContext* context, const v1::SetObservationModeRequest* request,
                                    v1::ControlCommandResponse* response) override {
        auto access = control_access(*context, request->phone_id(), request->request_id());
        if (!access.ok()) return access;
        if (!request->has_paused()) return {grpc::StatusCode::INVALID_ARGUMENT, "Missing observation mode"};
        *response = run_control(request->paused() ? "pause_monitor" : "resume_monitor", request->request_id());
        return grpc::Status::OK;
    }

    grpc::Status RecoverComponent(grpc::ServerContext* context, const v1::RecoverComponentRequest* request,
                                   v1::ControlCommandResponse* response) override {
        auto access = control_access(*context, request->phone_id(), request->request_id());
        if (!access.ok()) return access;
        const char* action = nullptr;
        switch (request->component()) {
            case v1::MONITOR_WIFI: action = "monitor"; break;
            case v1::BLE: action = "ble"; break;
            case v1::MGMT_WIFI: action = request->allow_hotspot_restart() ? "hotspot" : "check_hotspot"; break;
            case v1::TELEMETRY_CONNECTION:
                response->set_request_id(request->request_id());
                response->set_status(v1::UNSUPPORTED);
                response->set_reason("reconnect_on_phone");
                return grpc::Status::OK;
            default: return {grpc::StatusCode::INVALID_ARGUMENT, "Unknown recovery component"};
        }
        *response = run_control(action, request->request_id());
        return grpc::Status::OK;
    }

    grpc::Status Subscribe(grpc::ServerContext* context, const v1::SubscribeRequest* request,
                           grpc::ServerWriter<v1::TelemetryMessage>* stream) override {
        const auto& device = request->device_id();
        auto access = authorize_request(*context, device);
        if (!access.ok()) return access;
        {
            const std::lock_guard<std::mutex> guard(owner_lock_);
            if (!owner_.empty()) return {grpc::StatusCode::RESOURCE_EXHAUSTED, "Telemetry already has a subscriber"};
            owner_ = device;
            owner_accepts_risk_ = request->accepts_high_risk();
        }
        struct Release {
            TelemetryService& service;
            ~Release() {
                const std::lock_guard<std::mutex> guard(service.owner_lock_);
                service.owner_.clear();
                service.owner_accepts_risk_ = false;
            }
        } release{*this};

        try {
            DeadlineWriter writer(*context, *stream);
            auto snapshot = state_.snapshot();
            auto sequence = snapshot.sequence();
            const auto boot = snapshot.boot_id();
            v1::TelemetryMessage message;
            *message.mutable_snapshot() = std::move(snapshot);
            if (!writer.write(message)) return grpc::Status::OK;
            std::uint64_t cursor = request->last_event_sequence();
            const auto& previous_boot = request->last_boot_id();
            const bool session_changed = (!previous_boot.empty() || cursor != 0) && previous_boot != boot;
            if (session_changed || cursor > events_.latest()) {
                cursor = 0;
                if (!send_gap(writer, boot, cursor, "cursor_reset")) return grpc::Status::OK;
            }

            auto check_auth = Clock::now() + 2s;
            while (!context->IsCancelled()) {
                if (Clock::now() >= check_auth) {
                    access = authorize_request(*context, device);
                    if (!access.ok()) return access;
                    check_auth = Clock::now() + 2s;
                }
                snapshot = state_.snapshot();
                if (snapshot.sequence() != sequence) {
                    sequence = snapshot.sequence();
                    *message.mutable_snapshot() = std::move(snapshot);
                    if (!writer.write(message)) break;
                }
                if (request->accepts_high_risk()) {
                    if (auto pending = outbox_.next_for(device)) {
                        *message.mutable_high_risk() = std::move(*pending);
                        if (!writer.write(message)) break;
                    }
                }
                auto replay = events_.read_after(cursor);
                auto& next = replay.next;
                if (next) {
                    if (next->sequence() > cursor + 1 &&
                        !send_gap(writer, boot, next->sequence() - 1, "history_pruned")) break;
                    cursor = next->sequence();
                    *message.mutable_event() = std::move(*next);
                    if (!writer.write(message)) break;
                } else if (replay.latest > cursor) {
                    cursor = replay.latest;
                    if (!send_gap(writer, boot, cursor, "history_pruned")) break;
                } else {
                    std::this_thread::sleep_for(150ms);
                }
            }
        } catch (const std::exception&) {
            return {grpc::StatusCode::UNAVAILABLE, "Telemetry subscription unavailable"};
        }
        return grpc::Status::OK;
    }

private:
    static bool hex_id(const std::string& value) {
        return value.size() == 32 && value.find_first_not_of("0123456789abcdef") == std::string::npos;
    }
    bool owns_session(const std::string& phone, bool high_risk = false) {
        const std::lock_guard<std::mutex> guard(owner_lock_);
        return !owner_.empty() && owner_ == phone && (!high_risk || owner_accepts_risk_);
    }
    grpc::Status control_access(grpc::ServerContext& context, const std::string& phone, const std::string& request) {
        auto access = authorize_request(context, phone);
        if (!access.ok()) return access;
        if (!owns_session(phone)) return denied();
        if (!hex_id(request)) return {grpc::StatusCode::INVALID_ARGUMENT, "Invalid request ID"};
        return grpc::Status::OK;
    }
    grpc::Status authorize_request(grpc::ServerContext& context, const std::string& device) const {
        const auto auth = context.client_metadata().equal_range("authorization");
        if (auth.first == auth.second || std::next(auth.first) != auth.second) return denied();
        const auto& credential = auth.first->second;
        const std::string bearer(credential.data(), credential.size());
        if (bearer.size() != 50 || bearer.compare(0, 7, "Bearer ") != 0) return denied();
        return authorization(device, bearer.substr(7));
    }
    static grpc::Status denied() {
        return {grpc::StatusCode::PERMISSION_DENIED, "An active enrolled device is required"};
    }

    grpc::Status authorization(const std::string& device, const std::string& token) const {
        switch (authorize(registry_, device, token)) {
            case Authorization::active: return grpc::Status::OK;
            case Authorization::denied: return denied();
            case Authorization::unavailable:
                return {grpc::StatusCode::UNAVAILABLE, "Device registry unavailable"};
        }
        return denied();
    }

    static bool send_gap(DeadlineWriter& writer, const std::string& boot, std::uint64_t through,
                         const char* reason) {
        v1::TelemetryMessage message;
        auto* gap = message.mutable_history_gap();
        gap->set_boot_id(boot);
        gap->set_through_event_sequence(through);
        gap->set_reason(reason);
        return writer.write(message);
    }

    Runtime& state_;
    const EventStore& events_;
    HighRiskOutbox& outbox_;
    const std::string registry_;
    std::mutex owner_lock_;
    std::string owner_;
    bool owner_accepts_risk_ = false;
};

int run() {
    sigset_t signals;
    sigemptyset(&signals);
    sigaddset(&signals, SIGINT);
    sigaddset(&signals, SIGTERM);
    if (pthread_sigmask(SIG_BLOCK, &signals, nullptr) != 0) {
        throw std::runtime_error("Unable to set up service shutdown");
    }

    const auto listen = listen_address();
    const auto credentials = env("CREDENTIALS_DIRECTORY", "/etc/piagent-https");
    const auto directory = std::filesystem::path(credentials);
    grpc::SslServerCredentialsOptions tls;
    tls.pem_key_cert_pairs.push_back({
        text_file(env("PIAGENT_TELEMETRY_TLS_KEY", (directory / "server.key").c_str())),
        text_file(env("PIAGENT_TELEMETRY_TLS_CERT", (directory / "server.pem").c_str()))});
    const auto linux_boot = boot_id();
    EventStore events(linux_boot);
    HighRiskOutbox outbox(env("STATE_DIRECTORY"), linux_boot);
    Runtime state(events, KismetCollector(env("PIAGENT_KISMET_URL"), env("PIAGENT_KISMET_API_KEY")),
                  events.session_id(), linux_boot, &outbox);
    TelemetryService service(state, events, outbox,
                             env("PIAGENT_DEVICE_REGISTRY", "/var/lib/piagent-devices/devices.sqlite3"));

    grpc::ServerBuilder builder;
    grpc::ResourceQuota memory;
    memory.Resize(8 * 1024 * 1024);
    builder.SetResourceQuota(memory);
    builder.SetSyncServerOption(grpc::ServerBuilder::SyncServerOption::MIN_POLLERS, 1);
    builder.SetSyncServerOption(grpc::ServerBuilder::SyncServerOption::MAX_POLLERS, 2);
    builder.SetMaxReceiveMessageSize(4096);
    builder.SetMaxSendMessageSize(256 * 1024);
    builder.AddChannelArgument("grpc.http2.write_buffer_size", 32 * 1024);
    builder.AddListeningPort(listen, grpc::SslServerCredentials(tls));
    builder.RegisterService(&service);
    const auto server = builder.BuildAndStart();
    if (!server) throw std::runtime_error("Unable to bind the TLS telemetry listener");
    std::cout << "PocketNet telemetry listening on " << listen << std::endl;
    int received = 0;
    sigwait(&signals, &received);
    server->Shutdown(std::chrono::system_clock::now() + 2s);
    server->Wait();
    return 0;
}
}  // namespace
}  // namespace pocketnet::telemetry

int main() {
    try {
        return pocketnet::telemetry::run();
    } catch (const std::exception& error) {
        std::cerr << "Telemetry startup failed: " << error.what() << '\n';
        return 1;
    }
}
