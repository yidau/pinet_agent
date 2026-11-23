#include "event_store.hpp"
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
    TelemetryService(const Runtime& state, const EventStore& events, std::string registry)
        : state_(state), events_(events), registry_(std::move(registry)) {}

    grpc::Status Subscribe(grpc::ServerContext* context, const v1::SubscribeRequest* request,
                           grpc::ServerWriter<v1::TelemetryMessage>* stream) override {
        const auto auth = context->client_metadata().equal_range("authorization");
        if (auth.first == auth.second || std::next(auth.first) != auth.second) return denied();
        const auto& credential = auth.first->second;
        const std::string bearer(credential.data(), credential.size());
        if (bearer.size() != 50 || bearer.compare(0, 7, "Bearer ") != 0) return denied();
        const std::string token = bearer.substr(7);
        const auto& device = request->device_id();
        auto access = authorization(device, token);
        if (!access.ok()) return access;
        if (busy_.test_and_set()) {
            return {grpc::StatusCode::RESOURCE_EXHAUSTED, "Telemetry already has a subscriber"};
        }
        struct Release {
            std::atomic_flag& busy;
            ~Release() { busy.clear(); }
        } release{busy_};

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
            const auto delimiter = previous_boot.rfind(':');
            const bool journal_changed = delimiter != std::string::npos &&
                previous_boot.substr(delimiter + 1) != events_.generation();
            if (journal_changed || cursor > events_.latest()) {
                cursor = 0;
                if (!send_gap(writer, boot, cursor, "cursor_reset")) return grpc::Status::OK;
            }

            auto check_auth = Clock::now() + 2s;
            while (!context->IsCancelled()) {
                if (Clock::now() >= check_auth) {
                    access = authorization(device, token);
                    if (!access.ok()) return access;
                    check_auth = Clock::now() + 2s;
                }
                snapshot = state_.snapshot();
                if (snapshot.sequence() != sequence) {
                    sequence = snapshot.sequence();
                    *message.mutable_snapshot() = std::move(snapshot);
                    if (!writer.write(message)) break;
                }
                // Read the watermark before the row so concurrent appends cannot
                // cause a retained event to be skipped as a missing range.
                const auto latest = events_.latest();
                auto next = events_.next(cursor);
                if (next) {
                    if (next->sequence() > cursor + 1 &&
                        !send_gap(writer, boot, next->sequence() - 1, "history_pruned")) break;
                    cursor = next->sequence();
                    *message.mutable_event() = std::move(*next);
                    if (!writer.write(message)) break;
                } else if (latest > cursor) {
                    cursor = latest;
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

    const Runtime& state_;
    const EventStore& events_;
    const std::string registry_;
    std::atomic_flag busy_ = ATOMIC_FLAG_INIT;
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
    EventStore events(env("PIAGENT_TELEMETRY_EVENTS", "/var/lib/piagent-telemetry/events.sqlite3"));
    Runtime state(events, KismetCollector(env("PIAGENT_KISMET_URL"), env("PIAGENT_KISMET_API_KEY")),
                  boot_id() + ":" + events.generation());
    TelemetryService service(state, events, env("PIAGENT_DEVICE_REGISTRY", "/var/lib/piagent-devices/devices.sqlite3"));

    grpc::ServerBuilder builder;
    grpc::ResourceQuota memory;
    memory.Resize(8 * 1024 * 1024);
    builder.SetResourceQuota(memory);
    builder.SetSyncServerOption(grpc::ServerBuilder::SyncServerOption::MIN_POLLERS, 1);
    builder.SetSyncServerOption(grpc::ServerBuilder::SyncServerOption::MAX_POLLERS, 2);
    builder.SetMaxReceiveMessageSize(4096);
    builder.SetMaxSendMessageSize(64 * 1024);
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
