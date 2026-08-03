#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

#include "management_model.h"

namespace agentmeter {

inline constexpr size_t kMaximumSettingsBlobBytes = 512;

struct SettingsBlob {
  std::array<uint8_t, kMaximumSettingsBlobBytes> bytes{};
  uint16_t length = 0;
};

enum class SettingsDecodeStatus : uint8_t {
  Ok = 0,
  TooLarge = 1,
  Malformed = 2,
  UnsupportedVersion = 3,
  InvalidChecksum = 4,
  InvalidModel = 5,
};

struct LegacySettings {
  bool always_on = false;
  bool full_view = false;
  uint8_t rotation_seconds = kMinimumRotationSeconds;
  ProviderIdList hidden_provider_ids{};
};

bool encode_settings_blob(const DeviceSettings& settings, SettingsBlob& output);
SettingsDecodeStatus decode_settings_blob(const uint8_t* bytes, size_t length,
                                          DeviceSettings& output);
bool migrate_legacy_settings(const LegacySettings& legacy,
                             DeviceSettings& output);

}  // namespace agentmeter
