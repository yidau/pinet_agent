#pragma once
#include <string>

namespace pocketnet::telemetry {
enum class Authorization { denied, active, unavailable };

Authorization authorize(const std::string& registry, const std::string& device_id,
                        const std::string& token);
}  // namespace pocketnet::telemetry
