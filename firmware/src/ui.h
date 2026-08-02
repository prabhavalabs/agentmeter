#pragma once

#include <cstdint>

#include "dashboard_model.h"

namespace agentmeter {

enum class ConnectionState : uint8_t {
  Waiting,
  Connected,
  Reconnecting,
  Stale,
};

void ui_begin(const char* device_name);
void ui_set_model(const DashboardSnapshot& snapshot, uint32_t received_at_ms);
void ui_set_connection(ConnectionState state);
void ui_tick(uint32_t now_ms);
void ui_toggle_view();
void ui_show_pairing_cleared();

}  // namespace agentmeter
