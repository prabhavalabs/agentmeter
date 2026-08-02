#pragma once

#include <cstdint>

#include "dashboard_model.h"

namespace agentmeter {

using ModelCallback = void (*)(const DashboardSnapshot& snapshot,
                               uint32_t received_at_ms);

bool transport_begin(ModelCallback callback);
void transport_loop();
bool transport_is_connected();
const char* transport_device_name();
void transport_clear_bonds();

void serial_transport_poll(ModelCallback callback);
bool serial_transport_has_received();

}  // namespace agentmeter
