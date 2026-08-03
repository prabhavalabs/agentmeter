#pragma once

#include <cstdint>

#include "dashboard_model.h"
#include "management_model.h"

namespace agentmeter {

enum class ConnectionState : uint8_t {
  Waiting,
  Connected,
  Reconnecting,
  Stale,
};

using SettingsChangedCallback = void (*)(const DeviceSettings& settings,
                                         uint32_t changed_at_ms);

void ui_begin(const char* device_name, const DeviceSettings& initial_settings,
              SettingsChangedCallback settings_changed_callback);
void ui_set_model(const DashboardSnapshot& snapshot, uint32_t received_at_ms);
void ui_apply_settings(const DeviceSettings& settings);
void ui_set_connection(ConnectionState state);
void ui_tick(uint32_t now_ms);
void ui_toggle_view();
void ui_show_pairing_cleared();
void ui_identify();
bool ui_display_is_on();
bool ui_display_is_dimmed();

}  // namespace agentmeter
