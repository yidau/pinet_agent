#include "event_store.hpp"
#include "device_authorization.hpp"

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

void verify_history() {
    using telemetry::EventStore;
    EventStore store("boot-A", 2);
    check(store.read_after(0).oldest == 1, "empty buffer lower bound");
    const auto duplicate = event(v1::P3, "", "same");
    store.append({event(v1::P0, ""), duplicate, duplicate, event(v1::P2, "")});
    const auto first = store.read_after(0);
    check(first.latest == 3 && first.oldest == 2 && first.next && first.next->sequence() == 2,
          "FIFO retention and evidence deduplication");
    check(store.stats().count == 2 && store.stats().dropped == 1, "FIFO metrics");
    check(store.read_after(2).next->event_id() == store.session_id() + ":3", "resumed event ID");
    auto oversized = event(v1::P1, "");
    oversized.set_description(std::string(EventStore::max_event_bytes + 1, 'x'));
    store.append({oversized});
    const auto tail = store.read_after(3);
    check(tail.latest == 4 && !tail.next && store.stats().dropped == 2, "oversized tail gap");
    store.append({event(v1::P2, "")});
    check(store.read_after(3).next->sequence() == 5, "hole inside the replay range");

    EventStore byte_limited("boot-A", 100, 700);
    auto medium = event(v1::P1, "");
    medium.set_description(std::string(450, 'x'));
    byte_limited.append({medium, medium});
    check(byte_limited.stats().count == 1 && byte_limited.stats().bytes <= 700 &&
          byte_limited.read_after(0).oldest == 2, "byte-limited FIFO");
    EventStore tiny("boot-A", 10, 32);
    tiny.append({medium});
    check(tiny.read_after(0).oldest == 2 && tiny.latest() == 1 && tiny.stats().bytes == 0,
          "event larger than the configured budget");

    EventStore restarted("boot-A");
    EventStore rebooted("boot-B");
    check(restarted.latest() == 0 && restarted.session_id() != store.session_id(), "service restart identity");
    check(rebooted.latest() == 0 && rebooted.session_id().find("boot-B:") == 0, "system reboot identity");
    restarted.append({medium});
    check(restarted.read_after(0).next->event_id() == restarted.session_id() + ":1", "new session starts at one");
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
        verify_history();
        verify_authorization((fixture / "registry.db").string());
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        result = 1;
    }
    std::filesystem::remove_all(fixture);
    return result;
}
