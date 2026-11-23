#include "event_store.hpp"

#include <openssl/sha.h>
#include <sqlite3.h>

#include <algorithm>
#include <limits>
#include <memory>
#include <stdexcept>

namespace pocketnet::telemetry {
namespace {

using Statement = std::unique_ptr<sqlite3_stmt, decltype(&sqlite3_finalize)>;

void sql(sqlite3* db, const char* query) {
    if (sqlite3_exec(db, query, nullptr, nullptr, nullptr) != SQLITE_OK) {
        throw std::runtime_error(sqlite3_errmsg(db));
    }
}

Statement prepare(sqlite3* db, const char* query) {
    sqlite3_stmt* stmt{};
    if (sqlite3_prepare_v2(db, query, -1, &stmt, nullptr) != SQLITE_OK) {
        throw std::runtime_error(sqlite3_errmsg(db));
    }
    return {stmt, sqlite3_finalize};
}

int step(sqlite3* db, sqlite3_stmt* stmt) {
    const int result = sqlite3_step(stmt);
    if (result != SQLITE_DONE && result != SQLITE_ROW) {
        throw std::runtime_error(sqlite3_errmsg(db));
    }
    return result;
}

}  // namespace

EventStore::EventStore(const std::string& path, unsigned retention)
    : retention_(std::max(1u, retention)) {
    try {
        if (sqlite3_open_v2(path.c_str(), &db_, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nullptr) != SQLITE_OK) {
            throw std::runtime_error("Cannot open telemetry event history");
        }
        sqlite3_busy_timeout(db_, 1000);
        sql(db_, "CREATE TABLE IF NOT EXISTS events ("
                 "seq INTEGER PRIMARY KEY AUTOINCREMENT, priority INTEGER NOT NULL, "
                 "source TEXT NOT NULL, evidence_id TEXT, payload BLOB NOT NULL);"
                 "CREATE UNIQUE INDEX IF NOT EXISTS event_evidence ON events(source, evidence_id) "
                 "WHERE evidence_id IS NOT NULL;"
                 "CREATE TABLE IF NOT EXISTS journal_identity(id INTEGER PRIMARY KEY, generation TEXT NOT NULL);"
                 "INSERT OR IGNORE INTO journal_identity VALUES(1,lower(hex(randomblob(16))));");
        auto identity = prepare(db_, "SELECT generation FROM journal_identity WHERE id=1");
        if (step(db_, identity.get()) != SQLITE_ROW || sqlite3_column_bytes(identity.get(), 0) != 32) {
            throw std::runtime_error("Invalid telemetry journal identity");
        }
        generation_ = reinterpret_cast<const char*>(sqlite3_column_text(identity.get(), 0));
    } catch (...) {
        sqlite3_close(db_);
        throw;
    }
}

EventStore::~EventStore() {
    sqlite3_close(db_);
}

void EventStore::append(const std::vector<v1::MonitoringEvent>& events) {
    if (events.empty()) return;
    const std::lock_guard<std::mutex> guard(lock_);
    sql(db_, "BEGIN IMMEDIATE");
    try {
        auto insert = prepare(db_, "INSERT INTO events(priority,source,evidence_id,payload) "
                                   "SELECT ?1,?2,?3,?4 WHERE ?3 IS NULL OR NOT EXISTS "
                                   "(SELECT 1 FROM events WHERE source=?2 AND evidence_id=?3)");
        for (const auto& event : events) {
            const auto bytes = event.SerializeAsString();
            sqlite3_bind_int(insert.get(), 1, event.priority());
            sqlite3_bind_text(insert.get(), 2, event.source().c_str(), -1, SQLITE_TRANSIENT);
            if (event.evidence_id().empty()) {
                sqlite3_bind_null(insert.get(), 3);
            } else {
                sqlite3_bind_text(insert.get(), 3, event.evidence_id().c_str(), -1, SQLITE_TRANSIENT);
            }
            sqlite3_bind_blob(insert.get(), 4, bytes.data(), static_cast<int>(bytes.size()), SQLITE_TRANSIENT);
            step(db_, insert.get());
            sqlite3_reset(insert.get());
        }

        auto prune = prepare(db_, "DELETE FROM events WHERE seq IN (SELECT seq FROM events "
                                  "ORDER BY priority DESC,seq ASC LIMIT "
                                  "MAX(0,(SELECT COUNT(*) FROM events)-?1))");
        sqlite3_bind_int64(prune.get(), 1, retention_);
        step(db_, prune.get());
        sql(db_, "COMMIT");
    } catch (...) {
        sqlite3_exec(db_, "ROLLBACK", nullptr, nullptr, nullptr);
        throw;
    }
}

std::uint64_t EventStore::latest() const {
    const std::lock_guard<std::mutex> guard(lock_);
    auto query = prepare(db_, "SELECT seq FROM sqlite_sequence WHERE name='events'");
    if (step(db_, query.get()) != SQLITE_ROW) return 0;
    return static_cast<std::uint64_t>(sqlite3_column_int64(query.get(), 0));
}

std::optional<v1::MonitoringEvent> EventStore::next(std::uint64_t after) const {
    if (after >= static_cast<std::uint64_t>(std::numeric_limits<sqlite3_int64>::max())) return {};
    const std::lock_guard<std::mutex> guard(lock_);
    auto query = prepare(db_, "SELECT seq,payload FROM events WHERE seq>?1 ORDER BY seq LIMIT 1");
    sqlite3_bind_int64(query.get(), 1, static_cast<sqlite3_int64>(after));
    if (step(db_, query.get()) != SQLITE_ROW) return {};
    v1::MonitoringEvent event;
    if (!event.ParseFromArray(sqlite3_column_blob(query.get(), 1), sqlite3_column_bytes(query.get(), 1))) {
        throw std::runtime_error("Invalid telemetry event payload");
    }
    event.set_sequence(static_cast<std::uint64_t>(sqlite3_column_int64(query.get(), 0)));
    event.set_event_id(event.boot_id() + ":" + std::to_string(event.sequence()));
    return event;
}

Authorization authorize(const std::string& registry, const std::string& device_id,
                        const std::string& token) {
    if (device_id.size() != 32 || token.size() != 43) return Authorization::denied;
    if (device_id.find_first_not_of("0123456789abcdef") != std::string::npos ||
        token.find_first_not_of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_") != std::string::npos) {
        return Authorization::denied;
    }

    sqlite3* raw{};
    const int result = sqlite3_open_v2(registry.c_str(), &raw, SQLITE_OPEN_READONLY, nullptr);
    const std::unique_ptr<sqlite3, decltype(&sqlite3_close)> db(raw, sqlite3_close);
    if (result != SQLITE_OK) return Authorization::unavailable;
    sqlite3_busy_timeout(db.get(), 250);
    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256(reinterpret_cast<const unsigned char*>(token.data()), token.size(), hash);
    try {
        auto query = prepare(db.get(), "SELECT 1 FROM devices WHERE token_hash=?1 AND device_id=?2 AND status='active'");
        sqlite3_bind_blob(query.get(), 1, hash, sizeof(hash), SQLITE_TRANSIENT);
        sqlite3_bind_text(query.get(), 2, device_id.c_str(), -1, SQLITE_TRANSIENT);
        return step(db.get(), query.get()) == SQLITE_ROW ? Authorization::active : Authorization::denied;
    } catch (const std::runtime_error&) {
        return Authorization::unavailable;
    }
}

}  // namespace pocketnet::telemetry
