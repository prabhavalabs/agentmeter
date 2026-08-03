#pragma once

#include <cstdint>

#include "settings_codec.h"
#include "settings_model.h"

namespace agentmeter {

enum class SettingsLoadResult : uint8_t {
  Loaded,
  Migrated,
  Defaults,
  StorageError,
};

SettingsLoadResult load_device_settings(DeviceSettings& settings);
bool save_device_settings(const DeviceSettings& settings);

void load_dashboard_preferences(DashboardPreferences& preferences);
bool save_dashboard_preferences(const DashboardPreferences& preferences);

}  // namespace agentmeter
