#include "event_store.hpp"

#include <openssl/sha.h>
#include <sqlite3.h>

#include <filesystem>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <unistd.h>

using namespace pocketnet;

namespace {
void check(bool value, const char* reason) {
    if (!value) throw std::runtime_error(reason);
}

v1::MonitoringEvent event(v1::EventPriority priority, const std::string& boot,
                          const std::string& evidence = {}) {
    v1::MonitoringEvent value;
    value.set_priority(priority);
    value.set_boot_id(boot);
    value.set_source("test");
    if (!evidence.empty()) value.set_evidence_id(evidence);
    return value;
}

void verify_history(const std::string& path) {
    using telemetry::EventStore;
    std::string generation;
    {
        EventStore store(path, 3);
        generation = store.generation();
        check(generation.size() == 32, "invalid journal identity");
        check(store.latest() == 0, "new database has a sequence");
        store.append({event(v1::P0, "boot-A"), event(v1::P3, "boot-A", "same"),
                      event(v1::P3, "boot-A", "same"), event(v1::P1, "boot-A")});
        check(store.latest() == 3, "duplicate evidence advanced the cursor");
    }
    {
        EventStore store(path, 3);
        check(store.generation() == generation, "durable journal identity was lost");
        store.append({event(v1::P2, "boot-B")});
        check(store.latest() == 4, "durable sequence was lost");
        const auto first = store.next(0);
        const auto after_pruned = store.next(1);
        const auto last = store.next(3);
        check(first && first->event_id() == "boot-A:1", "critical event was pruned");
        check(after_pruned && after_pruned->sequence() == 3, "low-priority gap not detected");
        check(last && last->event_id() == "boot-B:4", "reboot event ID is incorrect");
        check(!store.next(4), "returned an event beyond the watermark");
    }
}

void verify_authorization(const std::string& path) {
    using telemetry::Authorization;
    using telemetry::authorize;
    sqlite3* raw = nullptr;
    const int opened = sqlite3_open(path.c_str(), &raw);
    const std::unique_ptr<sqlite3, decltype(&sqlite3_close)> db(raw, sqlite3_close);
    check(opened == SQLITE_OK, "fixture open failed");
    check(sqlite3_exec(raw, "CREATE TABLE devices(device_id TEXT, token_hash BLOB, status TEXT)",
                       nullptr, nullptr, nullptr) == SQLITE_OK, "fixture schema failed");
    const std::string token(43, 'A');
    const std::string device(32, '0');
    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256(reinterpret_cast<const unsigned char*>(token.data()), token.size(), hash);
    sqlite3_stmt* statement{};
    check(sqlite3_prepare_v2(raw, "INSERT INTO devices VALUES(?1,?2,'active')", -1, &statement, nullptr) == SQLITE_OK,
        "fixture prepare failed");
    const std::unique_ptr<sqlite3_stmt, decltype(&sqlite3_finalize)> row(statement, sqlite3_finalize);
    sqlite3_bind_text(statement, 1, device.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_blob(statement, 2, hash, sizeof(hash), SQLITE_TRANSIENT);
    check(sqlite3_step(statement) == SQLITE_DONE, "fixture insert failed");
    check(authorize(path, device, token) == Authorization::active, "valid enrolled device rejected");
    check(authorize(path, std::string(32, '1'), token) == Authorization::denied, "token accepted for wrong device");
    check(authorize(path, device, std::string(43, 'B')) == Authorization::denied, "wrong token accepted");
    check(authorize(path + ".missing", device, token) == Authorization::unavailable,
          "a missing registry was reported as rejected credentials");
    check(sqlite3_exec(raw, "UPDATE devices SET status='revoked'", nullptr, nullptr, nullptr) == SQLITE_OK,
        "fixture revocation failed");
    check(authorize(path, device, token) == Authorization::denied, "revoked device accepted");
}
}  // namespace

int main() {
    char location[] = "/tmp/piagent-event-store.XXXXXX";
    if (!mkdtemp(location)) return 1;
    const std::filesystem::path fixture(location);
    int result = 0;
    try {
        verify_history((fixture / "history.db").string());
        verify_authorization((fixture / "registry.db").string());
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        result = 1;
    }
    std::filesystem::remove_all(fixture);
    return result;
}
