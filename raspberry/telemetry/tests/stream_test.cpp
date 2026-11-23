#include "event_store.hpp"
#include "monitoring.grpc.pb.h"

#include <arpa/inet.h>
#include <grpcpp/grpcpp.h>
#include <openssl/sha.h>
#include <sqlite3.h>
#include <sys/wait.h>
#include <unistd.h>

#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <thread>

using namespace pocketnet;
using namespace std::chrono_literals;

namespace {
const std::string device_id(32, 'a');
const std::string token(43, 'X');

void check(bool condition, const char* error) {
    if (!condition) throw std::runtime_error(error);
}

void registry(const std::string& path, bool revoke = false) {
    sqlite3* raw = nullptr;
    const int opened = sqlite3_open(path.c_str(), &raw);
    const std::unique_ptr<sqlite3, decltype(&sqlite3_close)> database(raw, sqlite3_close);
    check(opened == SQLITE_OK, "open registry fixture");
    if (revoke) {
        check(sqlite3_exec(raw, "UPDATE devices SET status='revoked'", nullptr, nullptr, nullptr) == SQLITE_OK,
              "revoke registry fixture");
        return;
    }
    check(sqlite3_exec(raw, "CREATE TABLE devices(device_id TEXT,token_hash BLOB,status TEXT)",
                       nullptr, nullptr, nullptr) == SQLITE_OK, "create registry fixture");
    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256(reinterpret_cast<const unsigned char*>(token.data()), token.size(), hash);
    sqlite3_stmt* raw_insert{};
    check(sqlite3_prepare_v2(raw, "INSERT INTO devices VALUES(?1,?2,'active')", -1, &raw_insert, nullptr) ==
          SQLITE_OK, "prepare registry fixture");
    const std::unique_ptr<sqlite3_stmt, decltype(&sqlite3_finalize)> insert(raw_insert, sqlite3_finalize);
    sqlite3_bind_text(insert.get(), 1, device_id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_blob(insert.get(), 2, hash, sizeof(hash), SQLITE_TRANSIENT);
    check(sqlite3_step(insert.get()) == SQLITE_DONE, "insert registry fixture");
}

std::string loopback_address() {
    const int fd = socket(AF_INET, SOCK_STREAM, 0);
    check(fd >= 0, "temporary loopback socket");
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    socklen_t size = sizeof(addr);
    const bool ok = bind(fd, reinterpret_cast<sockaddr*>(&addr), size) == 0 &&
        getsockname(fd, reinterpret_cast<sockaddr*>(&addr), &size) == 0;
    close(fd);
    check(ok, "allocate loopback port");
    return "127.0.0.1:" + std::to_string(ntohs(addr.sin_port));
}

struct Child {
    pid_t pid;
    ~Child() {
        if (pid > 0) {
            kill(pid, SIGTERM);
            waitpid(pid, nullptr, 0);
        }
    }
};

std::string test_stream(const std::string& endpoint, const std::string& registry_path, const std::string& cert,
                        const std::string& previous, bool revoke) {
    grpc::SslCredentialsOptions tls;
    tls.pem_root_certs = cert;
    const auto channel = grpc::CreateChannel(endpoint, grpc::SslCredentials(tls));
    check(channel->WaitForConnected(std::chrono::system_clock::now() + 10s), "local TLS listener did not connect");
    auto client = v1::TelemetryService::NewStub(channel);
    v1::SubscribeRequest request;
    request.set_device_id(device_id);
    v1::TelemetryMessage message;
    {
        grpc::ClientContext context;
        context.set_deadline(std::chrono::system_clock::now() + 2s);
        auto stream = client->Subscribe(&context, request);
        check(!stream->Read(&message) && stream->Finish().error_code() == grpc::StatusCode::PERMISSION_DENIED,
              "stream accepted a request without a token");
    }
    {
        grpc::ClientContext context;
        context.set_deadline(std::chrono::system_clock::now() + 8s);
        context.AddMetadata("authorization", "Bearer " + token);
        request.set_last_boot_id(previous);
        request.set_last_event_sequence(1);
        auto stream = client->Subscribe(&context, request);
        check(stream->Read(&message) && message.has_snapshot() && message.snapshot().schema_version() == 1,
              "first message was not the current snapshot");
        const auto session = message.snapshot().boot_id();
        check(session != previous && session.size() == 69, "expected a unique Linux boot/process session");
        if (revoke) check(session.substr(0, 36) == previous.substr(0, 36), "expected the same Linux boot");
        check(stream->Read(&message) && message.has_history_gap() &&
              message.history_gap().reason() == "cursor_reset" &&
              message.history_gap().through_event_sequence() == 0,
              "journal replacement with a valid numeric cursor was not detected");
        while (stream->Read(&message) && message.has_snapshot()) {}
        check(message.has_event() && message.event().sequence() == 1 &&
              message.event().event_id() == session + ":1", "new session did not replay its first event");
        if (revoke) {
            registry(registry_path, true);
            while (stream->Read(&message)) {}
            check(stream->Finish().error_code() == grpc::StatusCode::PERMISSION_DENIED,
                  "revocation did not terminate the existing stream");
        } else {
            context.TryCancel();
            stream->Finish();
        }
        return session;
    }
}
}  // namespace

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    char directory[] = "/tmp/piagent-stream-test.XXXXXX";
    if (!mkdtemp(directory)) return 1;
    const std::string fixture(directory);
    int result = 0;
    try {
        const auto key = fixture + "/test.key";
        const auto pem = fixture + "/test.pem";
        const auto registry_path = fixture + "/registry.sqlite3";
        const auto openssl = "openssl req -new -x509 -nodes -newkey rsa:2048 -days 1 -subj /CN=127.0.0.1 "
                             "-addext subjectAltName=IP:127.0.0.1 -keyout " + key + " -out " + pem + " 2>/dev/null";
        check(std::system(openssl.c_str()) == 0, "could not generate isolated TLS fixture");
        registry(registry_path);
        std::ifstream certificate(pem);
        std::ostringstream trusted;
        trusted << certificate.rdbuf();

        std::string session = "prior-installation";
        for (bool revoke : {false, true}) {
            const auto endpoint = loopback_address();
            Child child{fork()};
            check(child.pid >= 0, "fork test server");
            if (child.pid == 0) {
                setenv("PIAGENT_TELEMETRY_LISTEN", endpoint.c_str(), 1);
                setenv("PIAGENT_TELEMETRY_TLS_KEY", key.c_str(), 1);
                setenv("PIAGENT_TELEMETRY_TLS_CERT", pem.c_str(), 1);
                setenv("PIAGENT_DEVICE_REGISTRY", registry_path.c_str(), 1);
                unsetenv("PIAGENT_KISMET_URL");
                unsetenv("PIAGENT_KISMET_API_KEY");
                execl(argv[1], argv[1], static_cast<char*>(nullptr));
                _exit(127);
            }
            session = test_stream(endpoint, registry_path, trusted.str(), session, revoke);
        }
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        result = 1;
    }
    std::filesystem::remove_all(fixture);
    return result;
}
