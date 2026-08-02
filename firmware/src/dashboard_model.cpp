#include "dashboard_model.h"

#include <ArduinoJson.h>

#include <cstring>
#include <type_traits>

namespace agentmeter {
namespace {

static_assert(std::is_trivially_copyable_v<DashboardSnapshot>);

// BLE and USB frames are applied from the Arduino loop task. Keeping the
// atomic parse candidate in static storage avoids placing the bounded provider
// model on that task's small stack while still publishing only valid snapshots.
DashboardSnapshot parse_candidate{};

bool copy_text(JsonVariantConst value,
               std::array<char, kDeviceTextBytes>& destination) {
  if (!value.is<const char*>()) {
    return false;
  }
  const char* text = value.as<const char*>();
  const size_t length = std::strlen(text);
  if (length == 0 || length >= destination.size()) {
    return false;
  }
  std::memcpy(destination.data(), text, length + 1);
  return true;
}

bool parse_provider_status(JsonVariantConst value, ProviderStatus& status) {
  if (!value.is<const char*>()) {
    return false;
  }
  const char* text = value.as<const char*>();
  if (std::strcmp(text, "ok") == 0) {
    status = ProviderStatus::Ok;
  } else if (std::strcmp(text, "stale") == 0) {
    status = ProviderStatus::Stale;
  } else if (std::strcmp(text, "error") == 0) {
    status = ProviderStatus::Error;
  } else if (std::strcmp(text, "unavailable") == 0) {
    status = ProviderStatus::Unavailable;
  } else {
    return false;
  }
  return true;
}

bool parse_event(JsonVariantConst input, DisplayEvent& event) {
  if (input.isNull()) {
    event.present = false;
    return true;
  }
  if (!input.is<JsonObjectConst>()) {
    return false;
  }
  const JsonObjectConst object = input.as<JsonObjectConst>();
  if (!object["id"].is<const char*>() ||
      !object["kind"].is<const char*>() ||
      !object["level"].is<const char*>() ||
      !object["expiresAtEpoch"].is<int64_t>()) {
    return false;
  }
  const char* id = object["id"].as<const char*>();
  const char* kind = object["kind"].as<const char*>();
  const char* level = object["level"].as<const char*>();
  const int64_t expires_at = object["expiresAtEpoch"].as<int64_t>();
  if (expires_at < 0) {
    return false;
  }
  const size_t id_length = std::strlen(id);
  if (id_length == 0 || id_length >= event.id.size()) {
    return false;
  }
  std::memcpy(event.id.data(), id, id_length + 1);

  if (std::strcmp(kind, "threshold") == 0) {
    event.kind = EventKind::Threshold;
  } else if (std::strcmp(kind, "reset") == 0) {
    event.kind = EventKind::Reset;
  } else if (std::strcmp(kind, "provider_error") == 0) {
    event.kind = EventKind::ProviderError;
  } else {
    return false;
  }

  if (std::strcmp(level, "info") == 0) {
    event.level = EventLevel::Info;
  } else if (std::strcmp(level, "warning") == 0) {
    event.level = EventLevel::Warning;
  } else if (std::strcmp(level, "critical") == 0) {
    event.level = EventLevel::Critical;
  } else {
    return false;
  }
  event.expires_at_epoch = expires_at;
  event.present = true;
  return true;
}

bool parse_display(JsonObjectConst input, DisplaySettings& display) {
  const int brightness = input["brightnessPercent"] | -1;
  const int64_t dim_after = input["dimAfterSeconds"] | -1;
  const int64_t screen_off = input["screenOffAfterSeconds"] | -1;
  const JsonArrayConst thresholds = input["alertThresholds"].as<JsonArrayConst>();
  if (brightness < 1 || brightness > 100 || dim_after < 30 ||
      screen_off < dim_after || screen_off > 86400 || thresholds.size() < 1 ||
      thresholds.size() > display.alert_thresholds.size() ||
      !input["soundEnabled"].is<bool>()) {
    return false;
  }

  display.brightness_percent = static_cast<uint8_t>(brightness);
  display.dim_after_seconds = static_cast<uint32_t>(dim_after);
  display.screen_off_after_seconds = static_cast<uint32_t>(screen_off);
  display.alert_threshold_count = static_cast<uint8_t>(thresholds.size());
  uint8_t previous = 0;
  size_t index = 0;
  for (JsonVariantConst threshold : thresholds) {
    const int value = threshold.as<int>();
    if (!threshold.is<int>() || value < 1 || value > 100 || value <= previous) {
      return false;
    }
    display.alert_thresholds[index++] = static_cast<uint8_t>(value);
    previous = static_cast<uint8_t>(value);
  }
  display.sound_enabled = input["soundEnabled"].as<bool>();
  return true;
}

bool parse_window(JsonObjectConst input, QuotaWindow& window) {
  if (!copy_text(input["kind"], window.kind) ||
      !copy_text(input["label"], window.label)) {
    return false;
  }
  const JsonVariantConst percent = input["usedPercent"];
  if (percent.isNull()) {
    window.used_percent = -1;
  } else if (percent.is<int>()) {
    const int value = percent.as<int>();
    if (value < 0 || value > 100) {
      return false;
    }
    window.used_percent = static_cast<int16_t>(value);
  } else {
    return false;
  }

  const JsonVariantConst reset = input["resetAtEpoch"];
  if (reset.isNull()) {
    window.has_reset = false;
  } else if (reset.is<int64_t>() && reset.as<int64_t>() >= 0) {
    window.has_reset = true;
    window.reset_at_epoch = reset.as<int64_t>();
  } else {
    return false;
  }
  return true;
}

bool parse_provider(JsonObjectConst input, ProviderSnapshot& provider) {
  if (!copy_text(input["id"], provider.id) ||
      !copy_text(input["name"], provider.name) ||
      !parse_provider_status(input["status"], provider.status)) {
    return false;
  }
  const JsonArrayConst windows = input["windows"].as<JsonArrayConst>();
  if (windows.isNull() || windows.size() > provider.windows.size()) {
    return false;
  }
  provider.window_count = static_cast<uint8_t>(windows.size());
  size_t index = 0;
  for (JsonObjectConst window : windows) {
    if (!parse_window(window, provider.windows[index++])) {
      return false;
    }
  }
  return true;
}

}  // namespace

ParseStatus parse_snapshot(const uint8_t* payload, size_t length,
                           DashboardSnapshot& output) {
  if (payload == nullptr || length == 0) {
    return ParseStatus::InvalidJson;
  }
  if (length > kMaximumSnapshotBytes) {
    return ParseStatus::TooLarge;
  }

  JsonDocument document;
  const DeserializationError error = deserializeJson(document, payload, length);
  if (error || !document.is<JsonObject>()) {
    return ParseStatus::InvalidJson;
  }
  const JsonObjectConst root = document.as<JsonObjectConst>();
  if (!root["schemaVersion"].is<int>() || root["schemaVersion"].as<int>() != 1) {
    return ParseStatus::UnsupportedSchema;
  }

  const int message_id = root["messageId"] | -1;
  const int64_t generated_at = root["generatedAtEpoch"] | -1;
  const int64_t stale_after = root["staleAfterSeconds"] | -1;
  const JsonArrayConst providers = root["providers"].as<JsonArrayConst>();
  const JsonObjectConst display = root["display"].as<JsonObjectConst>();
  if (message_id < 0 || message_id > 65535 || generated_at < 0 ||
      stale_after < 30 || stale_after > 3600 || providers.isNull() ||
      providers.size() > kMaximumProviders || display.isNull()) {
    return ParseStatus::InvalidModel;
  }

  std::memset(&parse_candidate, 0, sizeof(parse_candidate));
  parse_candidate.schema_version = 1;
  DashboardSnapshot& candidate = parse_candidate;
  candidate.message_id = static_cast<uint16_t>(message_id);
  candidate.generated_at_epoch = generated_at;
  candidate.stale_after_seconds = static_cast<uint32_t>(stale_after);
  candidate.provider_count = static_cast<uint8_t>(providers.size());
  size_t provider_index = 0;
  for (JsonObjectConst provider : providers) {
    if (!parse_provider(provider, candidate.providers[provider_index])) {
      return ParseStatus::InvalidModel;
    }
    for (size_t previous = 0; previous < provider_index; ++previous) {
      if (std::strcmp(candidate.providers[previous].id.data(),
                      candidate.providers[provider_index].id.data()) == 0) {
        return ParseStatus::InvalidModel;
      }
    }
    ++provider_index;
  }
  if (!parse_display(display, candidate.display) ||
      !parse_event(root["event"], candidate.event)) {
    return ParseStatus::InvalidModel;
  }

  output = candidate;
  return ParseStatus::Ok;
}

int64_t estimated_epoch(const DashboardSnapshot& snapshot,
                        uint32_t received_at_ms, uint32_t now_ms) {
  return snapshot.generated_at_epoch +
         static_cast<int64_t>((now_ms - received_at_ms) / 1000U);
}

int64_t seconds_until_reset(int64_t reset_at_epoch, int64_t now_epoch) {
  return reset_at_epoch > now_epoch ? reset_at_epoch - now_epoch : 0;
}

bool is_stale(const DashboardSnapshot& snapshot, uint32_t received_at_ms,
              uint32_t now_ms) {
  return (now_ms - received_at_ms) / 1000U > snapshot.stale_after_seconds;
}

}  // namespace agentmeter
