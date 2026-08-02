#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

#include "dashboard_model.h"

namespace agentmeter {

inline constexpr uint8_t kMinimumRotationSeconds = 3;
inline constexpr uint8_t kMaximumRotationSeconds = 60;
inline constexpr uint8_t kNoProviderIndex = 0xFF;

struct DashboardPreferences {
  bool always_on = false;
  bool full_view = false;
  uint8_t rotation_seconds = kMinimumRotationSeconds;
  std::array<std::array<char, kDeviceTextBytes>, kMaximumProviders>
      hidden_provider_ids{};
  uint8_t hidden_provider_count = 0;
};

bool is_provider_visible(const DashboardPreferences& preferences,
                         const char* provider_id);
bool set_provider_visible(DashboardPreferences& preferences,
                          const char* provider_id, bool visible);
bool set_rotation_seconds(DashboardPreferences& preferences, uint8_t seconds);
uint8_t visible_provider_indices(
    const DashboardSnapshot& snapshot,
    const DashboardPreferences& preferences,
    std::array<uint8_t, kMaximumProviders>& output);
uint8_t next_visible_provider(const DashboardSnapshot& snapshot,
                              const DashboardPreferences& preferences,
                              uint8_t current_index);
bool encode_hidden_provider_ids(const DashboardPreferences& preferences,
                                char* output, size_t output_size);
bool decode_hidden_provider_ids(const char* encoded,
                                DashboardPreferences& preferences);

}  // namespace agentmeter
