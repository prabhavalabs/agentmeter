#pragma once

#include <cstddef>
#include <cstdint>

#include "dashboard_model.h"
#include "management_protocol.h"

namespace agentmeter {

using ModelCallback = void (*)(const DashboardSnapshot& snapshot,
                               uint32_t received_at_ms);
using ManagementCallback = void (*)(const ManagementRequest& request,
                                    uint32_t received_at_ms);

bool transport_begin(ModelCallback model_callback,
                     ManagementCallback management_callback);
void transport_loop();
bool transport_publish_management(uint8_t message_type, uint16_t message_id,
                                  const uint8_t* payload, size_t length);
bool transport_is_connected();
const char* transport_device_name();
void transport_clear_bonds();

void serial_transport_poll(ModelCallback callback);
bool serial_transport_has_received();

}  // namespace agentmeter
