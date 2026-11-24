#pragma once

#include "monitoring.pb.h"

#include <string>

namespace pocketnet::telemetry {

v1::ControlCommandResponse run_control(const char* action, const std::string& request_id);
v1::CapturePolicyStatus capture_policy();
void add_component_health(v1::MonitoringSnapshot& snapshot);

}  // namespace pocketnet::telemetry
