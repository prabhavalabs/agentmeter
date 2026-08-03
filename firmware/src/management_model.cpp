#include "management_model.h"

#include <cctype>
#include <cstdio>
#include <cstring>

namespace agentmeter {
namespace {

bool validate_provider_id_list(const ProviderIdList& list) {
  if (list.count > list.values.size()) {
    return false;
  }
  for (uint8_t index = 0; index < list.count; ++index) {
    const char* provider_id = list.values[index].data();
    if (!is_valid_provider_id(provider_id)) {
      return false;
    }
    for (uint8_t previous = 0; previous < index; ++previous) {
      if (std::strcmp(list.values[previous].data(), provider_id) == 0) {
        return false;
      }
    }
  }
  return true;
}

bool validate_thresholds(const DeviceSettings& settings) {
  if (settings.alert_threshold_count == 0 ||
      settings.alert_threshold_count > settings.alert_thresholds.size()) {
    return false;
  }
  uint8_t previous = 0;
  for (uint8_t index = 0; index < settings.alert_threshold_count; ++index) {
    const uint8_t threshold = settings.alert_thresholds[index];
    if (threshold < 1 || threshold > 100 || threshold <= previous) {
      return false;
    }
    previous = threshold;
  }
  return true;
}

int snapshot_provider_index(const DashboardSnapshot& snapshot,
                            const char* provider_id) {
  for (uint8_t index = 0; index < snapshot.provider_count; ++index) {
    if (std::strcmp(snapshot.providers[index].id.data(), provider_id) == 0) {
      return index;
    }
  }
  return -1;
}

bool provider_index_already_added(
    const std::array<uint8_t, kMaximumProviders>& output, uint8_t count,
    uint8_t provider_index) {
  for (uint8_t index = 0; index < count; ++index) {
    if (output[index] == provider_index) {
      return true;
    }
  }
  return false;
}

bool provider_id_lists_equal(const ProviderIdList& left,
                             const ProviderIdList& right) {
  if (left.count != right.count) {
    return false;
  }
  for (uint8_t index = 0; index < left.count; ++index) {
    if (std::strcmp(left.values[index].data(), right.values[index].data()) != 0) {
      return false;
    }
  }
  return true;
}

}  // namespace

bool is_valid_provider_id(const char* provider_id) {
  if (provider_id == nullptr) {
    return false;
  }
  const size_t length = std::strlen(provider_id);
  if (length == 0 || length >= kDeviceTextBytes) {
    return false;
  }
  for (size_t index = 0; index < length; ++index) {
    const unsigned char value =
        static_cast<unsigned char>(provider_id[index]);
    if (!std::islower(value) && !std::isdigit(value) && value != '_' &&
        value != '-') {
      return false;
    }
  }
  return true;
}

bool provider_id_list_contains(const ProviderIdList& list,
                               const char* provider_id) {
  if (provider_id == nullptr || list.count > list.values.size()) {
    return false;
  }
  for (uint8_t index = 0; index < list.count; ++index) {
    if (std::strcmp(list.values[index].data(), provider_id) == 0) {
      return true;
    }
  }
  return false;
}

bool validate_device_settings(const DeviceSettings& settings,
                              const DashboardSnapshot* snapshot) {
  if (settings.rotation_seconds < kMinimumRotationSeconds ||
      settings.rotation_seconds > kMaximumRotationSeconds ||
      settings.brightness_percent < kMinimumBrightnessPercent ||
      settings.brightness_percent > kMaximumBrightnessPercent ||
      settings.dim_after_seconds < kMinimumDimAfterSeconds ||
      settings.dim_after_seconds > kMaximumDimAfterSeconds ||
      settings.screen_off_after_seconds < kMinimumScreenOffAfterSeconds ||
      settings.screen_off_after_seconds > kMaximumScreenOffAfterSeconds ||
      settings.screen_off_after_seconds < settings.dim_after_seconds ||
      !validate_thresholds(settings) ||
      !validate_provider_id_list(settings.hidden_provider_ids) ||
      !validate_provider_id_list(settings.provider_order)) {
    return false;
  }

  if (snapshot != nullptr && snapshot->provider_count > 0) {
    bool has_visible_provider = false;
    for (uint8_t index = 0; index < snapshot->provider_count; ++index) {
      if (!provider_id_list_contains(
              settings.hidden_provider_ids,
              snapshot->providers[index].id.data())) {
        has_visible_provider = true;
        break;
      }
    }
    if (!has_visible_provider) {
      return false;
    }
  }
  return true;
}

ManagementStatus apply_settings_patch(const SettingsPatch& patch,
                                      const DashboardSnapshot* snapshot,
                                      DeviceSettings& settings) {
  DeviceSettings candidate = settings;
  if (patch.has_always_on) {
    candidate.always_on = patch.always_on;
  }
  if (patch.has_full_view) {
    candidate.full_view = patch.full_view;
  }
  if (patch.has_rotation_seconds) {
    candidate.rotation_seconds = patch.rotation_seconds;
  }
  if (patch.has_brightness_percent) {
    candidate.brightness_percent = patch.brightness_percent;
  }
  if (patch.has_dim_after_seconds) {
    candidate.dim_after_seconds = patch.dim_after_seconds;
  }
  if (patch.has_screen_off_after_seconds) {
    candidate.screen_off_after_seconds = patch.screen_off_after_seconds;
  }
  if (patch.has_alert_thresholds) {
    candidate.alert_thresholds = patch.alert_thresholds;
    candidate.alert_threshold_count = patch.alert_threshold_count;
  }
  if (patch.has_sound_enabled) {
    candidate.sound_enabled = patch.sound_enabled;
  }
  if (patch.has_hidden_provider_ids) {
    candidate.hidden_provider_ids = patch.hidden_provider_ids;
  }
  if (patch.has_provider_order) {
    candidate.provider_order = patch.provider_order;
  }

  if (!validate_device_settings(candidate, snapshot)) {
    return ManagementStatus::InvalidRequest;
  }
  settings = candidate;
  return ManagementStatus::Ok;
}

uint8_t ordered_visible_provider_indices(
    const DashboardSnapshot& snapshot, const DeviceSettings& settings,
    std::array<uint8_t, kMaximumProviders>& output) {
  uint8_t count = 0;
  for (uint8_t index = 0; index < settings.provider_order.count; ++index) {
    const char* provider_id = settings.provider_order.values[index].data();
    if (provider_id_list_contains(settings.hidden_provider_ids, provider_id)) {
      continue;
    }
    const int provider_index = snapshot_provider_index(snapshot, provider_id);
    if (provider_index >= 0) {
      output[count++] = static_cast<uint8_t>(provider_index);
    }
  }

  for (uint8_t provider_index = 0; provider_index < snapshot.provider_count;
       ++provider_index) {
    const char* provider_id = snapshot.providers[provider_index].id.data();
    if (provider_id_list_contains(settings.hidden_provider_ids, provider_id) ||
        provider_index_already_added(output, count, provider_index)) {
      continue;
    }
    output[count++] = provider_index;
  }
  return count;
}

bool set_provider_order(DeviceSettings& settings,
                        const char* const* provider_ids, uint8_t count) {
  if (count > kMaximumProviders || (count > 0 && provider_ids == nullptr)) {
    return false;
  }
  ProviderIdList candidate{};
  candidate.count = count;
  for (uint8_t index = 0; index < count; ++index) {
    if (!is_valid_provider_id(provider_ids[index]) ||
        provider_id_list_contains(candidate, provider_ids[index])) {
      return false;
    }
    std::snprintf(candidate.values[index].data(), kDeviceTextBytes, "%s",
                  provider_ids[index]);
  }
  settings.provider_order = candidate;
  return true;
}

bool device_settings_equal(const DeviceSettings& left,
                           const DeviceSettings& right) {
  return left.revision == right.revision &&
         left.always_on == right.always_on &&
         left.full_view == right.full_view &&
         left.rotation_seconds == right.rotation_seconds &&
         left.brightness_percent == right.brightness_percent &&
         left.dim_after_seconds == right.dim_after_seconds &&
         left.screen_off_after_seconds == right.screen_off_after_seconds &&
         left.alert_thresholds == right.alert_thresholds &&
         left.alert_threshold_count == right.alert_threshold_count &&
         left.sound_enabled == right.sound_enabled &&
         provider_id_lists_equal(left.hidden_provider_ids,
                                 right.hidden_provider_ids) &&
         provider_id_lists_equal(left.provider_order, right.provider_order);
}

}  // namespace agentmeter
