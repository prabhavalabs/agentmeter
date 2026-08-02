#include "settings_model.h"

#include <cctype>
#include <cstdio>
#include <cstring>

namespace agentmeter {
namespace {

bool valid_provider_id(const char* provider_id) {
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

int hidden_provider_index(const DashboardPreferences& preferences,
                          const char* provider_id) {
  for (uint8_t index = 0; index < preferences.hidden_provider_count; ++index) {
    if (std::strcmp(preferences.hidden_provider_ids[index].data(),
                    provider_id) == 0) {
      return index;
    }
  }
  return -1;
}

}  // namespace

bool is_provider_visible(const DashboardPreferences& preferences,
                         const char* provider_id) {
  return hidden_provider_index(preferences, provider_id) < 0;
}

bool set_provider_visible(DashboardPreferences& preferences,
                          const char* provider_id, bool visible) {
  if (!valid_provider_id(provider_id)) {
    return false;
  }
  const int index = hidden_provider_index(preferences, provider_id);
  if (visible) {
    if (index < 0) {
      return true;
    }
    for (uint8_t current = static_cast<uint8_t>(index);
         current + 1 < preferences.hidden_provider_count; ++current) {
      preferences.hidden_provider_ids[current] =
          preferences.hidden_provider_ids[current + 1];
    }
    --preferences.hidden_provider_count;
    preferences.hidden_provider_ids[preferences.hidden_provider_count].fill(0);
    return true;
  }
  if (index >= 0) {
    return true;
  }
  if (preferences.hidden_provider_count >=
      preferences.hidden_provider_ids.size()) {
    return false;
  }
  std::snprintf(
      preferences.hidden_provider_ids[preferences.hidden_provider_count].data(),
      kDeviceTextBytes, "%s", provider_id);
  ++preferences.hidden_provider_count;
  return true;
}

bool set_rotation_seconds(DashboardPreferences& preferences, uint8_t seconds) {
  if (seconds < kMinimumRotationSeconds ||
      seconds > kMaximumRotationSeconds) {
    return false;
  }
  preferences.rotation_seconds = seconds;
  return true;
}

uint8_t visible_provider_indices(
    const DashboardSnapshot& snapshot,
    const DashboardPreferences& preferences,
    std::array<uint8_t, kMaximumProviders>& output) {
  uint8_t count = 0;
  for (uint8_t index = 0; index < snapshot.provider_count; ++index) {
    if (is_provider_visible(preferences, snapshot.providers[index].id.data())) {
      output[count++] = index;
    }
  }
  return count;
}

uint8_t next_visible_provider(const DashboardSnapshot& snapshot,
                              const DashboardPreferences& preferences,
                              uint8_t current_index) {
  if (snapshot.provider_count == 0) {
    return kNoProviderIndex;
  }
  for (uint8_t offset = 1; offset <= snapshot.provider_count; ++offset) {
    const uint8_t candidate =
        static_cast<uint8_t>((current_index + offset) % snapshot.provider_count);
    if (is_provider_visible(preferences,
                            snapshot.providers[candidate].id.data())) {
      return candidate;
    }
  }
  return kNoProviderIndex;
}

bool encode_hidden_provider_ids(const DashboardPreferences& preferences,
                                char* output, size_t output_size) {
  if (output == nullptr || output_size == 0) {
    return false;
  }
  output[0] = '\0';
  size_t used = 0;
  for (uint8_t index = 0; index < preferences.hidden_provider_count; ++index) {
    const char* provider_id = preferences.hidden_provider_ids[index].data();
    const size_t length = std::strlen(provider_id);
    const size_t separator = index == 0 ? 0 : 1;
    if (used + separator + length + 1 > output_size) {
      output[0] = '\0';
      return false;
    }
    if (separator != 0) {
      output[used++] = ',';
    }
    std::memcpy(output + used, provider_id, length);
    used += length;
    output[used] = '\0';
  }
  return true;
}

bool decode_hidden_provider_ids(const char* encoded,
                                DashboardPreferences& preferences) {
  if (encoded == nullptr) {
    return false;
  }
  DashboardPreferences candidate = preferences;
  candidate.hidden_provider_count = 0;
  for (auto& provider_id : candidate.hidden_provider_ids) {
    provider_id.fill(0);
  }
  if (encoded[0] == '\0') {
    preferences = candidate;
    return true;
  }

  const char* start = encoded;
  while (*start != '\0') {
    const char* end = std::strchr(start, ',');
    const size_t length = end == nullptr ? std::strlen(start)
                                         : static_cast<size_t>(end - start);
    if (length == 0 || length >= kDeviceTextBytes ||
        candidate.hidden_provider_count >=
            candidate.hidden_provider_ids.size()) {
      return false;
    }
    std::array<char, kDeviceTextBytes> provider_id{};
    std::memcpy(provider_id.data(), start, length);
    if (!valid_provider_id(provider_id.data()) ||
        !set_provider_visible(candidate, provider_id.data(), false)) {
      return false;
    }
    if (end == nullptr) {
      break;
    }
    start = end + 1;
  }
  preferences = candidate;
  return true;
}

}  // namespace agentmeter
