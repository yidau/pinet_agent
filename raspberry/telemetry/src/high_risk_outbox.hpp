#pragma once

#include "monitoring.pb.h"

#include <condition_variable>
#include <atomic>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <functional>
#include <future>
#include <list>
#include <mutex>
#include <optional>
#include <thread>

struct sqlite3;

namespace pocketnet::telemetry {

std::int64_t boottime_ms();
std::string random_id();

class HighRiskOutbox {
public:
    using Clock = std::function<std::int64_t()>;

    HighRiskOutbox(std::filesystem::path directory, std::string boot,
                   Clock clock = boottime_ms, std::uint64_t budget = 32 * 1024 * 1024);
    ~HighRiskOutbox();
    HighRiskOutbox(const HighRiskOutbox&) = delete;
    HighRiskOutbox& operator=(const HighRiskOutbox&) = delete;

    // Completes true only once a transaction has committed (or an already
    // committed duplicate was found). Never block the Kismet collector on disk I/O.
    std::future<bool> submit(v1::MonitoringEvent event);
    std::optional<v1::HighRiskEnvelope> next_for(const std::string& phone);
    std::string acknowledge(const std::string& phone, const std::string& id);
    v1::HighRiskDeliveryStatus status() const;

private:
    struct Record {
        v1::HighRiskEnvelope envelope;
        std::int64_t created;
        std::uint64_t size;
        std::int64_t retry_at = 0;
        std::string offered_to;
    };
    struct Job {
        v1::MonitoringEvent event;
        std::string phone;
        std::string id;
        std::shared_ptr<std::promise<std::string>> completion;
        std::shared_ptr<std::promise<bool>> persisted;
    };
    struct Receipt {
        std::string id;
        std::string owner;
        std::string outcome;
    };

    void work();
    void open(sqlite3* db);
    void sweep(sqlite3* db, std::int64_t now);
    bool insert(sqlite3* db, v1::MonitoringEvent event);
    std::string delete_ack(sqlite3* db, const std::string& phone, const std::string& id);
    void remember(Receipt receipt);
    void publish_status();

    const std::filesystem::path directory_;
    const std::string boot_;
    const Clock clock_;
    const std::uint64_t budget_;
    mutable std::mutex mutex_;
    std::mutex jobs_mutex_;
    mutable std::mutex status_mutex_;
    std::condition_variable wake_;
    std::deque<Job> jobs_;
    std::list<Record> records_;
    std::deque<Receipt> receipts_;
    v1::HighRiskDeliveryStatus counters_;
    v1::HighRiskDeliveryStatus reported_;
    std::atomic<bool> storage_ready_{false};
    std::atomic<std::uint64_t> queue_errors_{0};
    std::atomic<std::uint64_t> queue_rejected_{0};
    std::atomic<std::uint64_t> too_large_{0};
    std::uint64_t bytes_ = 0;
    bool stopping_ = false;
    std::thread thread_;
};

}  // namespace pocketnet::telemetry
