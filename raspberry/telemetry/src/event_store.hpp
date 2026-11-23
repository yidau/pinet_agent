#pragma once

#include "monitoring.pb.h"

#include <cstdint>
#include <deque>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace pocketnet::telemetry {

class EventStore {
public:
    static constexpr std::size_t max_event_bytes = 60 * 1024;
    explicit EventStore(std::string linux_boot_id, std::size_t max_events = 4096,
                        std::size_t max_bytes = 16 * 1024 * 1024);

    struct Replay {
        std::uint64_t latest;
        // Empty buffers report latest + 1.
        std::uint64_t oldest;
        std::optional<v1::MonitoringEvent> next;
    };
    struct Stats {
        std::size_t count;
        std::size_t bytes;
        std::uint64_t dropped;
    };

    void append(const std::vector<v1::MonitoringEvent>& events);
    std::uint64_t latest() const;
    Replay read_after(std::uint64_t after) const;
    Stats stats() const;
    const std::string& session_id() const { return session_id_; }

private:
    const std::string session_id_;
    const std::size_t max_events_;
    const std::size_t max_bytes_;
    mutable std::mutex lock_;
    std::deque<v1::MonitoringEvent> events_;
    // Views refer to immutable strings in the deque and are erased before popping.
    std::set<std::pair<std::string_view, std::string_view>> evidence_;
    std::uint64_t sequence_{};
    std::uint64_t dropped_{};
    std::size_t bytes_{};
};

}  // namespace pocketnet::telemetry
