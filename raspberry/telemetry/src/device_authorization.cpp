#include "device_authorization.hpp"

#include <openssl/sha.h>
#include <sqlite3.h>
#include <memory>
#include <stdexcept>

namespace pocketnet::telemetry {
namespace {
using Statement = std::unique_ptr<sqlite3_stmt, decltype(&sqlite3_finalize)>;

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
