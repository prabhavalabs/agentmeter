#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

#include "dashboard_model.h"

namespace agentmeter {

inline constexpr uint8_t kManagementSchemaVersion = 1;
inline constexpr size_t kMaximumManagementBytes = 2048;
inline constexpr uint8_t kMinimumRotationSeconds = 3;
inline constexpr uint8_t kMaximumRotationSeconds = 60;
inline constexpr uint8_t kMinimumBrightnessPercent = 1;
inline constexpr uint8_t kMaximumBrightnessPercent = 100;
inline constexpr uint32_t kMinimumDimAfterSeconds = 30;
inline constexpr uint32_t kMaximumDimAfterSeconds = 3600;
inline constexpr uint32_t kMinimumScreenOffAfterSeconds = 60;
inline constexpr uint32_t kMaximumScreenOffAfterSeconds = 86400;

enum class ManagementStatus : uint8_t {
  Ok = 0,
  MalformedFrame = 1,
  TooLarge = 2,
  InvalidJson = 3,
  UnsupportedSchema = 4,
  InvalidRequest = 5,
  RevisionConflict = 6,
  UnsupportedCommand = 7,
  PersistenceFailed = 8,
};

struct ProviderIdList {
  std::array<std::array<char, kDeviceTextBytes>, kMaximumProviders> values{};
  uint8_t count = 0;
};

struct DeviceSettings {
  uint32_t revision = 0;
  bool always_on = false;
  bool full_view = false;
  uint8_t rotation_seconds = kMinimumRotationSeconds;
  uint8_t brightness_percent = 55;
  uint32_t dim_after_seconds = 300;
  uint32_t screen_off_after_seconds = 1800;
  std::array<uint8_t, 3> alert_thresholds{75, 90, 0};
  uint8_t alert_threshold_count = 2;
  bool sound_enabled = false;
  ProviderIdList hidden_provider_ids{};
  ProviderIdList provider_order{};
};

struct SettingsPatch {
  uint32_t base_revision = 0;
  bool has_always_on = false;
  bool always_on = false;
  bool has_full_view = false;
  bool full_view = false;
  bool has_rotation_seconds = false;
  uint8_t rotation_seconds = kMinimumRotationSeconds;
  bool has_brightness_percent = false;
  uint8_t brightness_percent = 55;
  bool has_dim_after_seconds = false;
  uint32_t dim_after_seconds = 300;
  bool has_screen_off_after_seconds = false;
  uint32_t screen_off_after_seconds = 1800;
  bool has_alert_thresholds = false;
  std::array<uint8_t, 3> alert_thresholds{};
  uint8_t alert_threshold_count = 0;
  bool has_sound_enabled = false;
  bool sound_enabled = false;
  bool has_hidden_provider_ids = false;
  ProviderIdList hidden_provider_ids{};
  bool has_provider_order = false;
  ProviderIdList provider_order{};
};

enum class PowerSource : uint8_t { Unknown, Usb, Battery };

struct DeviceInformation {
  std::array<char, kDeviceTextBytes> model{};
  std::array<char, kDeviceTextBytes> name{};
  std::array<char, 16> firmware_version{};
  std::array<char, 16> hardware_revision{};
  uint8_t snapshot_schema_version = 1;
  uint8_t management_schema_version = kManagementSchemaVersion;
  bool supports_settings = true;
  bool supports_identify = true;
  bool supports_restart = true;
  bool supports_forget = true;
  bool supports_brightness = true;
  bool supports_battery = false;
  bool supports_vbus_voltage = false;
  bool supports_input_current = false;
};

struct DeviceTelemetry {
  uint32_t uptime_seconds = 0;
  uint32_t free_heap_bytes = 0;
  uint32_t minimum_free_heap_bytes = 0;
  bool display_on = true;
  bool display_dimmed = false;
  uint8_t brightness_percent = 55;
  PowerSource power_source = PowerSource::Unknown;
  bool usb_present = false;
  bool battery_present = false;
  bool has_charging = false;
  bool charging = false;
  bool has_battery_voltage = false;
  uint16_t battery_voltage_mv = 0;
  bool has_battery_percent = false;
  uint8_t battery_percent = 0;
  bool has_vbus_voltage = false;
  uint16_t vbus_voltage_mv = 0;
  bool has_input_current = false;
  uint16_t input_current_ma = 0;
  bool has_board_temperature = false;
  float board_temperature_c = 0.0F;
};

struct DeviceState {
  DeviceInformation information{};
  DeviceTelemetry telemetry{};
  DeviceSettings settings{};
};

bool is_valid_provider_id(const char* provider_id);
bool provider_id_list_contains(const ProviderIdList& list,
                               const char* provider_id);
bool validate_device_settings(const DeviceSettings& settings,
                              const DashboardSnapshot* snapshot);
ManagementStatus apply_settings_patch(const SettingsPatch& patch,
                                      const DashboardSnapshot* snapshot,
                                      DeviceSettings& settings);
uint8_t ordered_visible_provider_indices(
    const DashboardSnapshot& snapshot, const DeviceSettings& settings,
    std::array<uint8_t, kMaximumProviders>& output);
bool set_provider_order(DeviceSettings& settings, const char* const* provider_ids,
                        uint8_t count);
bool device_settings_equal(const DeviceSettings& left,
                           const DeviceSettings& right);

}  // namespace agentmeter
