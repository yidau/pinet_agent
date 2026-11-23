#pragma once

#include "monitoring.pb.h"

#include <cstdint>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

struct sqlite3;

namespace pocketnet::telemetry {

class EventStore {
public:
    explicit EventStore(const std::string& path, unsigned retention = 4096);
    ~EventStore();
    EventStore(const EventStore&) = delete;
    EventStore& operator=(const EventStore&) = delete;

    void append(const std::vector<v1::MonitoringEvent>& events);
    std::uint64_t latest() const;
    std::optional<v1::MonitoringEvent> next(std::uint64_t after) const;
    const std::string& generation() const { return generation_; }

private:
    sqlite3* db_{};
    const unsigned retention_;
    std::string generation_;
    mutable std::mutex lock_;
};

enum class Authorization { denied, active, unavailable };

Authorization authorize(const std::string& registry, const std::string& device_id,
                        const std::string& token);

}  // namespace pocketnet::telemetry
