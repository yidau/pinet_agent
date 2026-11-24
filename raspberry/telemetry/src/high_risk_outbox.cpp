#include "high_risk_outbox.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <ctime>
#include <memory>
#include <stdexcept>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

#include <openssl/rand.h>
#include <sqlite3.h>

namespace pocketnet::telemetry {
namespace {
constexpr std::int64_t ttl_ms = 180000;
constexpr std::int64_t retry_ms = 3000;
constexpr std::uint64_t record_limit = 60 * 1024;
constexpr std::size_t job_limit = 128;
constexpr std::size_t row_limit = 4096;

void execute(sqlite3* db, const char* sql) {
    if (sqlite3_exec(db, sql, nullptr, nullptr, nullptr) != SQLITE_OK) {
        throw std::runtime_error("Outbox database operation failed");
    }
}

struct Statement {
    sqlite3_stmt* value = nullptr;
    Statement(sqlite3* db, const char* sql) {
        if (sqlite3_prepare_v2(db, sql, -1, &value, nullptr) != SQLITE_OK) {
            throw std::runtime_error("Cannot prepare outbox operation");
        }
    }
    ~Statement() { sqlite3_finalize(value); }
    void text(int index, const std::string& value_text) {
        if (sqlite3_bind_text(value, index, value_text.data(), value_text.size(), SQLITE_TRANSIENT) != SQLITE_OK) {
            throw std::runtime_error("Cannot bind outbox text");
        }
    }
    void blob(int index, const std::string& data) {
        if (sqlite3_bind_blob(value, index, data.data(), data.size(), SQLITE_TRANSIENT) != SQLITE_OK) {
            throw std::runtime_error("Cannot bind outbox payload");
        }
    }
    void integer(int index, std::int64_t number) {
        if (sqlite3_bind_int64(value, index, number) != SQLITE_OK) {
            throw std::runtime_error("Cannot bind outbox number");
        }
    }
    void done() {
        if (sqlite3_step(value) != SQLITE_DONE) throw std::runtime_error("Cannot persist outbox change");
    }
};

class Transaction {
public:
    explicit Transaction(sqlite3* db) : db_(db) { execute(db_, "BEGIN IMMEDIATE"); }
    ~Transaction() { if (!committed_) sqlite3_exec(db_, "ROLLBACK", nullptr, nullptr, nullptr); }
    void commit() { execute(db_, "COMMIT"); committed_ = true; }
private:
    sqlite3* db_;
    bool committed_ = false;
};

void erase(sqlite3* db, const std::string& id) {
    Statement remove(db, "DELETE FROM outbox WHERE id = ?");
    remove.text(1, id);
    remove.done();
}

bool valid_event(const v1::MonitoringEvent& event) {
    return event.event_category() == v1::SECURITY &&
           (event.risk_class() == v1::HIGH || event.risk_class() == v1::CRITICAL);
}
}  // namespace

std::int64_t boottime_ms() {
    timespec value{};
    if (clock_gettime(CLOCK_BOOTTIME, &value) != 0) throw std::runtime_error("Linux boot clock unavailable");
    return std::int64_t(value.tv_sec) * 1000 + value.tv_nsec / 1000000;
}

std::string random_id() {
    std::array<unsigned char, 16> bytes{};
    if (RAND_bytes(bytes.data(), bytes.size()) != 1) throw std::runtime_error("Secure random unavailable");
    std::string id;
    id.reserve(32);
    constexpr char hex[] = "0123456789abcdef";
    for (auto byte : bytes) {
        id.push_back(hex[byte >> 4]);
        id.push_back(hex[byte & 15]);
    }
    return id;
}

HighRiskOutbox::HighRiskOutbox(std::filesystem::path directory, std::string boot, Clock clock, std::uint64_t budget)
    : directory_(std::move(directory)), boot_(std::move(boot)), clock_(std::move(clock)), budget_(budget),
      thread_(&HighRiskOutbox::work, this) {}

HighRiskOutbox::~HighRiskOutbox() {
    {
        const std::lock_guard<std::mutex> guard(jobs_mutex_);
        stopping_ = true;
    }
    wake_.notify_one();
    thread_.join();
}

void HighRiskOutbox::submit(v1::MonitoringEvent event) {
    if (!valid_event(event)) return;
    const std::lock_guard<std::mutex> guard(jobs_mutex_);
    if (event.ByteSizeLong() > record_limit - 64) {
        ++too_large_;
    } else if (!storage_ready_) {
        ++queue_errors_;
    } else if (jobs_.size() == job_limit) {
        ++queue_rejected_;
    } else {
        jobs_.push_back({std::move(event), {}, {}, {}});
        wake_.notify_one();
    }
}

std::optional<v1::HighRiskEnvelope> HighRiskOutbox::next_for(const std::string& phone) {
    const std::unique_lock<std::mutex> guard(mutex_, std::try_to_lock);
    if (!guard.owns_lock() || !storage_ready_) return std::nullopt;
    const auto now = clock_();
    auto best = records_.end();
    for (auto record = records_.begin(); record != records_.end(); ++record) {
        if (now - record->created >= ttl_ms || (record->offered_to == phone && now < record->retry_at)) continue;
        if (best == records_.end() || record->envelope.event().risk_class() > best->envelope.event().risk_class()) {
            best = record;
        }
    }
    if (best == records_.end()) return std::nullopt;
    best->offered_to = phone;
    best->retry_at = now + retry_ms;
    return best->envelope;
}

std::string HighRiskOutbox::acknowledge(const std::string& phone, const std::string& id) {
    auto completion = std::make_shared<std::promise<std::string>>();
    auto result = completion->get_future();
    {
        const std::lock_guard<std::mutex> guard(jobs_mutex_);
        if (!storage_ready_ || jobs_.size() == job_limit || stopping_) return "unavailable";
        jobs_.push_front({{}, phone, id, std::move(completion)});
    }
    wake_.notify_one();
    return result.wait_for(std::chrono::seconds(2)) == std::future_status::ready ? result.get() : "unavailable";
}

v1::HighRiskDeliveryStatus HighRiskOutbox::status() const {
    const std::lock_guard<std::mutex> guard(status_mutex_);
    auto result = reported_;
    result.set_storage_error_count(result.storage_error_count() + queue_errors_);
    result.set_overflow_rejected_count(result.overflow_rejected_count() + queue_rejected_);
    result.set_oversize_rejected_count(result.oversize_rejected_count() + too_large_);
    return result;
}

void HighRiskOutbox::publish_status() {
    const std::lock_guard<std::mutex> guard(status_mutex_);
    reported_ = counters_;
    reported_.set_pending_count(records_.size());
    reported_.set_pending_bytes(bytes_);
}

void HighRiskOutbox::open(sqlite3* db) {
    execute(db, "PRAGMA page_size=4096");
    execute(db, "PRAGMA journal_mode=DELETE");
    execute(db, "PRAGMA synchronous=FULL");
    execute(db, "PRAGMA cache_size=-1024");
    {
        Statement limit(db, "PRAGMA max_page_count=9216");
        if (sqlite3_step(limit.value) != SQLITE_ROW || sqlite3_column_int(limit.value, 0) > 9216) {
            throw std::runtime_error("Outbox exceeds its physical page budget");
        }
    }
    execute(db, "CREATE TABLE IF NOT EXISTS outbox("
                "id TEXT PRIMARY KEY, boot TEXT NOT NULL, created INTEGER NOT NULL,"
                "payload BLOB NOT NULL, CHECK(length(payload)<=61440))");
    execute(db, "CREATE TABLE IF NOT EXISTS signatures ("
                "signature TEXT PRIMARY KEY, boot TEXT NOT NULL, created INTEGER NOT NULL)");
    Statement old_signatures(db, "DELETE FROM signatures WHERE boot<>?");
    old_signatures.text(1, boot_);
    old_signatures.done();
    Statement previous(db, "DELETE FROM outbox WHERE boot<>?");
    previous.text(1, boot_);
    previous.done();
    counters_.set_previous_boot_discarded_count(sqlite3_changes(db));
    Statement expired(db, "DELETE FROM outbox WHERE created <= ? OR created > ?");
    const auto now = clock_();
    expired.integer(1, now - ttl_ms);
    expired.integer(2, now);
    expired.done();
    counters_.set_expired_count(sqlite3_changes(db));
    Statement rows(db, "SELECT id,created,payload FROM outbox ORDER BY created,rowid");
    int state;
    while ((state = sqlite3_step(rows.value)) == SQLITE_ROW) {
        Record item{};
        item.created = sqlite3_column_int64(rows.value, 1);
        item.size = sqlite3_column_bytes(rows.value, 2);
        if (records_.size() >= row_limit || item.size > record_limit || bytes_ + item.size > budget_ ||
            !item.envelope.ParseFromArray(sqlite3_column_blob(rows.value, 2), item.size) ||
            !valid_event(item.envelope.event()) ||
            item.envelope.durable_id() != reinterpret_cast<const char*>(sqlite3_column_text(rows.value, 0))) {
            throw std::runtime_error("Invalid durable queue record");
        }
        bytes_ += item.size;
        records_.push_back(std::move(item));
    }
    if (state != SQLITE_DONE) throw std::runtime_error("Cannot load durable queue");
    counters_.set_storage_available(true);
}

void HighRiskOutbox::remember(Receipt receipt) {
    if (receipts_.size() >= row_limit) receipts_.pop_front();
    receipts_.push_back(std::move(receipt));
}

void HighRiskOutbox::sweep(sqlite3* db, std::int64_t now) {
    if (records_.empty() || now - records_.front().created < ttl_ms) return;
    Statement remove(db, "DELETE FROM outbox WHERE created <= ?");
    remove.integer(1, now - ttl_ms);
    remove.done();
    while (!records_.empty() && now - records_.front().created >= ttl_ms) {
        auto& item = records_.front();
        remember({item.envelope.durable_id(), std::move(item.offered_to), "expired"});
        bytes_ -= item.size;
        records_.pop_front();
        counters_.set_expired_count(counters_.expired_count() + 1);
    }
}

void HighRiskOutbox::insert(sqlite3* db, v1::MonitoringEvent event) {
    const auto now = clock_();
    if (!event.event_id().empty()) {
        Statement duplicate(db, "SELECT 1 FROM signatures WHERE signature=? AND created>?");
        duplicate.text(1, event.event_id());
        duplicate.integer(2, now - 300000);
        if (sqlite3_step(duplicate.value) == SQLITE_ROW) return;
    }
    Record item{};
    item.envelope.set_durable_id(random_id());
    item.envelope.set_ttl_seconds(ttl_ms / 1000);
    const auto wall = std::chrono::system_clock::now().time_since_epoch();
    item.envelope.set_enqueued_wall_ms(std::chrono::duration_cast<std::chrono::milliseconds>(wall).count());
    *item.envelope.mutable_event() = std::move(event);
    const auto payload = item.envelope.SerializeAsString();
    item.size = payload.size();
    if (item.size > record_limit) {
        counters_.set_oversize_rejected_count(counters_.oversize_rejected_count() + 1);
        return;
    }
    std::vector<std::list<Record>::iterator> candidates;
    if (bytes_ + item.size > budget_ || records_.size() >= row_limit) {
        for (auto row = records_.begin(); row != records_.end(); ++row) {
            if (row->envelope.event().risk_class() <= item.envelope.event().risk_class()) candidates.push_back(row);
        }
        std::stable_sort(candidates.begin(), candidates.end(), [](const auto& a, const auto& b) {
            return a->envelope.event().risk_class() < b->envelope.event().risk_class();
        });
    }
    auto remaining = bytes_;
    std::size_t count = 0;
    while ((remaining + item.size > budget_ || records_.size() - count >= row_limit) && count < candidates.size()) {
        remaining -= candidates[count++]->size;
    }
    if (remaining + item.size > budget_ || records_.size() - count >= row_limit) {
        counters_.set_overflow_rejected_count(counters_.overflow_rejected_count() + 1);
        return;
    }
    if (std::filesystem::space(directory_).available < 16 * 1024 * 1024) {
        throw std::runtime_error("Insufficient free space for the durable queue");
    }
    Transaction transaction(db);
    for (std::size_t i = 0; i < count; ++i) erase(db, candidates[i]->envelope.durable_id());
    Statement add(db, "INSERT INTO outbox(id,boot,created,payload) VALUES(?,?,?,?)");
    item.created = clock_();
    add.text(1, item.envelope.durable_id());
    add.text(2, boot_);
    add.integer(3, item.created);
    add.blob(4, payload);
    add.done();
    if (!item.envelope.event().event_id().empty()) {
        Statement trim(db, "DELETE FROM signatures WHERE created<=? OR rowid IN "
                           "(SELECT rowid FROM signatures ORDER BY created DESC,rowid DESC LIMIT -1 OFFSET 4095)");
        trim.integer(1, now - 300000);
        trim.done();
        Statement signature(db, "INSERT OR REPLACE INTO signatures(signature,boot,created) VALUES(?,?,?)");
        signature.text(1, item.envelope.event().event_id());
        signature.text(2, boot_);
        signature.integer(3, now);
        signature.done();
    }
    transaction.commit();
    for (std::size_t i = 0; i < count; ++i) records_.erase(candidates[i]);
    bytes_ = remaining + item.size;
    counters_.set_overflow_evicted_count(counters_.overflow_evicted_count() + count);
    records_.push_back(std::move(item));
}

std::string HighRiskOutbox::delete_ack(sqlite3* db, const std::string& phone, const std::string& id) {
    const auto record = std::find_if(records_.begin(), records_.end(), [&](const auto& row) {
        return row.envelope.durable_id() == id && row.offered_to == phone;
    });
    if (record == records_.end()) {
        const auto receipt = std::find_if(receipts_.rbegin(), receipts_.rend(), [&](const auto& row) {
            return row.id == id && row.owner == phone;
        });
        return receipt == receipts_.rend() ? "unknown" : receipt->outcome;
    }
    if (clock_() - record->created >= ttl_ms) return "expired";
    erase(db, id);
    bytes_ -= record->size;
    records_.erase(record);
    remember({id, phone, "already_acked"});
    counters_.set_acked_count(counters_.acked_count() + 1);
    return "acked";
}

void HighRiskOutbox::work() {
    sqlite3* handle = nullptr;
    if (directory_.empty()) return;
    struct stat info{};
    std::error_code error;
    const auto resolved = std::filesystem::canonical(directory_, error);
    const auto dbpath = resolved / "outbox.sqlite3";
    const bool private_directory = stat(directory_.c_str(), &info) == 0 && S_ISDIR(info.st_mode) &&
                                   info.st_uid == geteuid() && (info.st_mode & 0077) == 0;
    const int result = private_directory && !error ? sqlite3_open_v2(dbpath.c_str(), &handle,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOFOLLOW, nullptr) : SQLITE_CANTOPEN;
    const std::unique_ptr<sqlite3, decltype(&sqlite3_close)> db(handle, sqlite3_close);
    try {
        if (result != SQLITE_OK) throw std::runtime_error("Cannot open private high risk outbox");
        open(db.get());
    } catch (const std::exception&) {
        counters_.set_storage_error_count(counters_.storage_error_count() + 1);
        publish_status();
        return;
    }
    storage_ready_ = true;
    publish_status();
    for (;;) {
        Job job;
        {
            std::unique_lock<std::mutex> guard(jobs_mutex_);
            wake_.wait_for(guard, std::chrono::seconds(1), [this] { return stopping_ || !jobs_.empty(); });
            if (jobs_.empty() && stopping_) break;
            if (!jobs_.empty()) {
                job = std::move(jobs_.front());
                jobs_.pop_front();
            }
        }
        const std::lock_guard<std::mutex> guard(mutex_);
        try {
            sweep(db.get(), clock_());
            if (job.completion) job.completion->set_value(delete_ack(db.get(), job.phone, job.id));
            else if (job.event.has_event_category()) insert(db.get(), std::move(job.event));
        } catch (const std::exception&) {
            counters_.set_storage_error_count(counters_.storage_error_count() + 1);
            if (job.completion) job.completion->set_value("unavailable");
        }
        publish_status();
    }
}

}  // namespace pocketnet::telemetry
