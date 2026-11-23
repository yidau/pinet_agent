#include "event_store.hpp"

#include <openssl/rand.h>
#include <algorithm>
#include <array>
#include <stdexcept>

namespace pocketnet::telemetry {
namespace {
std::string make_session_id(std::string boot) {
    std::array<unsigned char, 16> random{};
    if (RAND_bytes(random.data(), random.size()) != 1) {
        throw std::runtime_error("Cannot generate telemetry session ID");
    }
    constexpr char hex[] = "0123456789abcdef";
    boot += ':';
    for (const auto byte : random) {
        boot += hex[byte >> 4];
        boot += hex[byte & 15];
    }
    return boot;
}
}  // namespace

EventStore::EventStore(std::string linux_boot_id, std::size_t max_events,
                       std::size_t max_serialized_bytes)
    : session_id_(make_session_id(std::move(linux_boot_id))),
      max_events_(max_events), max_serialized_bytes_(max_serialized_bytes) {
    if (max_events_ == 0 || max_serialized_bytes_ == 0) {
        throw std::invalid_argument("Empty telemetry buffer budget");
    }
}

void EventStore::append(const std::vector<v1::MonitoringEvent>& events) {
    const std::lock_guard<std::mutex> guard(lock_);
    for (const auto& event : events) {
        const std::pair<std::string_view, std::string_view> key{event.source(), event.evidence_id()};
        if (!key.second.empty() && evidence_.count(key)) continue;

        auto assigned = event;
        assigned.set_sequence(++sequence_);
        assigned.set_boot_id(session_id_);
        assigned.set_event_id(session_id_ + ":" + std::to_string(sequence_));
        const auto bytes = assigned.ByteSizeLong();
        if (bytes > max_event_bytes || bytes > max_serialized_bytes_) {
            ++dropped_;
            continue;
        }

        while (events_.size() >= max_events_ || bytes_ > max_serialized_bytes_ - bytes) {
            const auto& oldest = events_.front();
            if (!oldest.evidence_id().empty()) evidence_.erase({oldest.source(), oldest.evidence_id()});
            bytes_ -= oldest.ByteSizeLong();
            events_.pop_front();
            ++dropped_;
        }
        auto& stored = events_.emplace_back(std::move(assigned));
        if (!stored.evidence_id().empty()) evidence_.emplace(stored.source(), stored.evidence_id());
        bytes_ += bytes;
    }
}

std::uint64_t EventStore::latest() const {
    const std::lock_guard<std::mutex> guard(lock_);
    return sequence_;
}

EventStore::Replay EventStore::read_after(std::uint64_t after) const {
    const std::lock_guard<std::mutex> guard(lock_);
    const auto oldest = events_.empty() ? sequence_ + 1 : events_.front().sequence();
    const auto next = std::upper_bound(events_.begin(), events_.end(), after,
        [](auto cursor, const auto& event) { return cursor < event.sequence(); });
    return {sequence_, oldest, next == events_.end() ? std::nullopt : std::optional{*next}};
}

EventStore::Stats EventStore::stats() const {
    const std::lock_guard<std::mutex> guard(lock_);
    return {events_.size(), bytes_, dropped_, max_events_, max_serialized_bytes_};
}

}  // namespace pocketnet::telemetry
