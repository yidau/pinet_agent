#include "high_risk_outbox.hpp"

#include <atomic>
#include <chrono>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <unistd.h>

using namespace pocketnet;
using namespace pocketnet::telemetry;

namespace {
struct Fixture {
    std::filesystem::path path;
    Fixture() {
        char directory[] = "/tmp/pocketnet-outbox-XXXXXX";
        const auto created = mkdtemp(directory);
        if (!created) throw std::runtime_error("temporary directory failed");
        path = created;
    }
    ~Fixture() { std::filesystem::remove_all(path); }
};

void verify(bool truth, const char* reason) {
    if (!truth) throw std::runtime_error(reason);
}

void wait_for(const std::function<bool()>& checked) {
    for (int tick = 0; tick < 200; ++tick) {
        if (checked()) return;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    throw std::runtime_error("async outbox condition timed out");
}

v1::MonitoringEvent native_alert(const char* id, v1::RiskClass risk, std::size_t size = 64) {
    v1::MonitoringEvent value;
    value.set_event_id(id);
    value.set_event_category(v1::SECURITY);
    value.set_risk_class(risk);
    value.set_description(std::string(size, 'a'));
    return value;
}
}  // namespace

int main() {
    try {
        Fixture fixture;
        std::atomic<std::int64_t> now{1000};
        auto clock = [&] { return now.load(); };
        std::string first;
        {
            HighRiskOutbox queue(fixture.path, "boot-a", clock);
            wait_for([&] { return queue.status().storage_available(); });
            auto first_result = queue.submit(native_alert("native-1", v1::HIGH));
            verify(first_result.get(), "high-risk enqueue only succeeds after durable commit");
            wait_for([&] { return queue.status().pending_count() == 1; });
            const auto delivery = queue.next_for("phone-a");
            verify(delivery.has_value(), "eligible after durable insert");
            first = delivery->durable_id();
            verify(queue.acknowledge("phone-b", first) == "unknown", "unoffered phone cannot acknowledge");
            verify(queue.status().pending_count() == 1, "delivery alone does not delete");
        }
        now = 180999;
        {
            HighRiskOutbox queue(fixture.path, "boot-a", clock);
            wait_for([&] { return queue.status().storage_available(); });
            const auto delivery = queue.next_for("phone-a");
            verify(delivery && delivery->durable_id() == first, "stable identity 1ms before expiry after process restart");
            now = 181000;
            verify(!queue.next_for("phone-a"), "no send at the 180 second boundary");
            verify(queue.acknowledge("phone-a", first) == "expired", "no ACK at the boundary");
            verify(queue.submit(native_alert("native-2", v1::CRITICAL)).get(), "persist critical event");
            wait_for([&] { return queue.status().pending_count() == 1; });
            const auto second = queue.next_for("phone-a");
            verify(second && queue.acknowledge("phone-a", second->durable_id()) == "acked", "valid durable ACK");
            verify(queue.acknowledge("phone-a", second->durable_id()) == "already_acked", "idempotent ACK");
            verify(queue.submit(native_alert("native-2", v1::CRITICAL)).get(),
                   "already committed event is safely deduplicated");
            verify(queue.submit(native_alert("native-3", v1::HIGH)).get(), "persist another event");
            wait_for([&] { return queue.status().pending_count() == 1; });
        }
        {
            HighRiskOutbox queue(fixture.path, "boot-b", clock, 350);
            wait_for([&] { return queue.status().storage_available(); });
            verify(queue.status().previous_boot_discarded_count() == 1, "discard across device boots");
            verify(queue.submit(native_alert("critical-first", v1::CRITICAL, 200)).get(), "persist first critical");
            verify(!queue.submit(native_alert("lower-priority", v1::HIGH, 200)).get(),
                   "risk-priority rejection reports failed durability");
            wait_for([&] { return queue.status().overflow_rejected_count() == 1; });
            verify(queue.submit(native_alert("critical-latest", v1::CRITICAL, 200)).get(),
                   "new critical evicts old at equal rank");
            wait_for([&] { return queue.status().overflow_evicted_count() == 1; });
            const auto latest = queue.next_for("phone-a");
            verify(latest && latest->event().event_id() == "critical-latest", "keep newest in the same risk class");
        }
        {
            HighRiskOutbox broken(fixture.path / "missing-state-dir", "boot-c", clock);
            wait_for([&] { return broken.status().storage_error_count() > 0; });
            auto rejected = broken.submit(native_alert("retry-me", v1::CRITICAL));
            verify(!rejected.get(), "unavailable SQLite must not claim durable success");
            verify(broken.status().storage_error_count() > 0, "failed storage exposes diagnostics");
        }
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
