#include "management_protocol.h"

#include <ArduinoJson.h>

#include <cstdio>
#include <cstring>

namespace agentmeter {
namespace {

bool key_is_allowed(const char* key, const char* const* allowed,
                    size_t allowed_count) {
  for (size_t index = 0; index < allowed_count; ++index) {
    if (std::strcmp(key, allowed[index]) == 0) {
      return true;
    }
  }
  return false;
}

bool has_only_keys(JsonObjectConst object, const char* const* allowed,
                   size_t allowed_count) {
  for (JsonPairConst pair : object) {
    if (!key_is_allowed(pair.key().c_str(), allowed, allowed_count)) {
      return false;
    }
  }
  return true;
}

bool has_key(JsonObjectConst object, const char* key) {
  for (JsonPairConst pair : object) {
    if (std::strcmp(pair.key().c_str(), key) == 0) {
      return true;
    }
  }
  return false;
}

bool parse_provider_ids(JsonVariantConst value, ProviderIdList& output) {
  if (!value.is<JsonArrayConst>()) {
    return false;
  }
  const JsonArrayConst array = value.as<JsonArrayConst>();
  if (array.size() > kMaximumProviders) {
    return false;
  }
  ProviderIdList candidate{};
  for (JsonVariantConst item : array) {
    if (!item.is<const char*>()) {
      return false;
    }
    const char* provider_id = item.as<const char*>();
    if (!is_valid_provider_id(provider_id) ||
        provider_id_list_contains(candidate, provider_id)) {
      return false;
    }
    std::snprintf(candidate.values[candidate.count].data(), kDeviceTextBytes,
                  "%s", provider_id);
    ++candidate.count;
  }
  output = candidate;
  return true;
}

bool parse_alert_thresholds(JsonVariantConst value, SettingsPatch& patch) {
  if (!value.is<JsonArrayConst>()) {
    return false;
  }
  const JsonArrayConst array = value.as<JsonArrayConst>();
  if (array.size() == 0 || array.size() > patch.alert_thresholds.size()) {
    return false;
  }
  std::array<uint8_t, 3> thresholds{};
  uint8_t previous = 0;
  uint8_t count = 0;
  for (JsonVariantConst item : array) {
    if (!item.is<int>()) {
      return false;
    }
    const int threshold = item.as<int>();
    if (threshold < 1 || threshold > 100 || threshold <= previous) {
      return false;
    }
    thresholds[count++] = static_cast<uint8_t>(threshold);
    previous = static_cast<uint8_t>(threshold);
  }
  patch.alert_thresholds = thresholds;
  patch.alert_threshold_count = count;
  return true;
}

ManagementStatus parse_settings_patch(JsonObjectConst payload,
                                      SettingsPatch& output) {
  static constexpr const char* kAllowedKeys[] = {
      "baseRevision",       "alwaysOn",      "fullView",
      "rotationSeconds",    "brightnessPercent",
      "dimAfterSeconds",    "screenOffAfterSeconds",
      "alertThresholds",    "soundEnabled",  "hiddenProviderIds",
      "providerOrder",
  };
  if (!has_only_keys(payload, kAllowedKeys,
                     sizeof(kAllowedKeys) / sizeof(kAllowedKeys[0])) ||
      payload.size() < 2 || !payload["baseRevision"].is<uint32_t>()) {
    return ManagementStatus::InvalidRequest;
  }

  SettingsPatch candidate{};
  candidate.base_revision = payload["baseRevision"].as<uint32_t>();
  if (has_key(payload, "alwaysOn")) {
    if (!payload["alwaysOn"].is<bool>()) {
      return ManagementStatus::InvalidRequest;
    }
    candidate.has_always_on = true;
    candidate.always_on = payload["alwaysOn"].as<bool>();
  }
  if (has_key(payload, "fullView")) {
    if (!payload["fullView"].is<bool>()) {
      return ManagementStatus::InvalidRequest;
    }
    candidate.has_full_view = true;
    candidate.full_view = payload["fullView"].as<bool>();
  }
  if (has_key(payload, "rotationSeconds")) {
    const int value = payload["rotationSeconds"] | -1;
    if (!payload["rotationSeconds"].is<int>() ||
        value < kMinimumRotationSeconds || value > kMaximumRotationSeconds) {
      return ManagementStatus::InvalidRequest;
    }
    candidate.has_rotation_seconds = true;
    candidate.rotation_seconds = static_cast<uint8_t>(value);
  }
  if (has_key(payload, "brightnessPercent")) {
    const int value = payload["brightnessPercent"] | -1;
    if (!payload["brightnessPercent"].is<int>() ||
        value < kMinimumBrightnessPercent ||
        value > kMaximumBrightnessPercent) {
      return ManagementStatus::InvalidRequest;
    }
    candidate.has_brightness_percent = true;
    candidate.brightness_percent = static_cast<uint8_t>(value);
  }
  if (has_key(payload, "dimAfterSeconds")) {
    const int64_t value = payload["dimAfterSeconds"] | -1;
    if (!payload["dimAfterSeconds"].is<int64_t>() ||
        value < kMinimumDimAfterSeconds || value > kMaximumDimAfterSeconds) {
      return ManagementStatus::InvalidRequest;
    }
    candidate.has_dim_after_seconds = true;
    candidate.dim_after_seconds = static_cast<uint32_t>(value);
  }
  if (has_key(payload, "screenOffAfterSeconds")) {
    const int64_t value = payload["screenOffAfterSeconds"] | -1;
    if (!payload["screenOffAfterSeconds"].is<int64_t>() ||
        value < kMinimumScreenOffAfterSeconds ||
        value > kMaximumScreenOffAfterSeconds) {
      return ManagementStatus::InvalidRequest;
    }
    candidate.has_screen_off_after_seconds = true;
    candidate.screen_off_after_seconds = static_cast<uint32_t>(value);
  }
  if (has_key(payload, "alertThresholds")) {
    if (!parse_alert_thresholds(payload["alertThresholds"], candidate)) {
      return ManagementStatus::InvalidRequest;
    }
    candidate.has_alert_thresholds = true;
  }
  if (has_key(payload, "soundEnabled")) {
    if (!payload["soundEnabled"].is<bool>()) {
      return ManagementStatus::InvalidRequest;
    }
    candidate.has_sound_enabled = true;
    candidate.sound_enabled = payload["soundEnabled"].as<bool>();
  }
  if (has_key(payload, "hiddenProviderIds")) {
    if (!parse_provider_ids(payload["hiddenProviderIds"],
                            candidate.hidden_provider_ids)) {
      return ManagementStatus::InvalidRequest;
    }
    candidate.has_hidden_provider_ids = true;
  }
  if (has_key(payload, "providerOrder")) {
    if (!parse_provider_ids(payload["providerOrder"],
                            candidate.provider_order)) {
      return ManagementStatus::InvalidRequest;
    }
    candidate.has_provider_order = true;
  }
  output = candidate;
  return ManagementStatus::Ok;
}

bool parse_command(const char* type, ManagementCommand& command) {
  if (std::strcmp(type, "device.get") == 0) {
    command = ManagementCommand::DeviceGet;
  } else if (std::strcmp(type, "telemetry.get") == 0) {
    command = ManagementCommand::TelemetryGet;
  } else if (std::strcmp(type, "settings.get") == 0) {
    command = ManagementCommand::SettingsGet;
  } else if (std::strcmp(type, "settings.patch") == 0) {
    command = ManagementCommand::SettingsPatch;
  } else if (std::strcmp(type, "device.identify") == 0) {
    command = ManagementCommand::DeviceIdentify;
  } else if (std::strcmp(type, "device.restart") == 0) {
    command = ManagementCommand::DeviceRestart;
  } else if (std::strcmp(type, "device.forget") == 0) {
    command = ManagementCommand::DeviceForget;
  } else {
    return false;
  }
  return true;
}

const char* result_type(ManagementCommand command) {
  switch (command) {
    case ManagementCommand::DeviceGet:
      return "device.result";
    case ManagementCommand::TelemetryGet:
      return "telemetry.result";
    case ManagementCommand::SettingsGet:
    case ManagementCommand::SettingsPatch:
      return "settings.result";
    case ManagementCommand::DeviceIdentify:
      return "identify.result";
    case ManagementCommand::DeviceRestart:
      return "restart.result";
    case ManagementCommand::DeviceForget:
      return "forget.result";
  }
  return "device.result";
}

const char* status_name(ManagementStatus status) {
  switch (status) {
    case ManagementStatus::Ok:
      return "ok";
    case ManagementStatus::MalformedFrame:
      return "malformedFrame";
    case ManagementStatus::TooLarge:
      return "tooLarge";
    case ManagementStatus::InvalidJson:
      return "invalidJson";
    case ManagementStatus::UnsupportedSchema:
      return "unsupportedSchema";
    case ManagementStatus::InvalidRequest:
      return "invalidRequest";
    case ManagementStatus::RevisionConflict:
      return "revisionConflict";
    case ManagementStatus::UnsupportedCommand:
      return "unsupportedCommand";
    case ManagementStatus::PersistenceFailed:
      return "persistenceFailed";
  }
  return "invalidRequest";
}

const char* power_source_name(PowerSource source) {
  switch (source) {
    case PowerSource::Usb:
      return "usb";
    case PowerSource::Battery:
      return "battery";
    case PowerSource::Unknown:
      return "unknown";
  }
  return "unknown";
}

void write_provider_ids(JsonArray output, const ProviderIdList& list) {
  for (uint8_t index = 0; index < list.count; ++index) {
    output.add(list.values[index].data());
  }
}

void write_settings(JsonObject output, const DeviceSettings& settings) {
  output["revision"] = settings.revision;
  output["alwaysOn"] = settings.always_on;
  output["fullView"] = settings.full_view;
  output["rotationSeconds"] = settings.rotation_seconds;
  output["brightnessPercent"] = settings.brightness_percent;
  output["dimAfterSeconds"] = settings.dim_after_seconds;
  output["screenOffAfterSeconds"] = settings.screen_off_after_seconds;
  JsonArray thresholds = output["alertThresholds"].to<JsonArray>();
  for (uint8_t index = 0; index < settings.alert_threshold_count; ++index) {
    thresholds.add(settings.alert_thresholds[index]);
  }
  output["soundEnabled"] = settings.sound_enabled;
  write_provider_ids(output["hiddenProviderIds"].to<JsonArray>(),
                     settings.hidden_provider_ids);
  write_provider_ids(output["providerOrder"].to<JsonArray>(),
                     settings.provider_order);
}

void write_telemetry(JsonObject output, const DeviceTelemetry& telemetry) {
  output["uptimeSeconds"] = telemetry.uptime_seconds;
  output["freeHeapBytes"] = telemetry.free_heap_bytes;
  output["minimumFreeHeapBytes"] = telemetry.minimum_free_heap_bytes;
  output["displayOn"] = telemetry.display_on;
  output["displayDimmed"] = telemetry.display_dimmed;
  output["brightnessPercent"] = telemetry.brightness_percent;
  output["powerSource"] = power_source_name(telemetry.power_source);
  output["usbPresent"] = telemetry.usb_present;
  output["batteryPresent"] = telemetry.battery_present;
  if (telemetry.has_charging) {
    output["charging"] = telemetry.charging;
  } else {
    output["charging"] = nullptr;
  }
  if (telemetry.has_battery_voltage) {
    output["batteryVoltageMv"] = telemetry.battery_voltage_mv;
  } else {
    output["batteryVoltageMv"] = nullptr;
  }
  if (telemetry.has_battery_percent) {
    output["batteryPercent"] = telemetry.battery_percent;
  } else {
    output["batteryPercent"] = nullptr;
  }
  if (telemetry.has_vbus_voltage) {
    output["vbusVoltageMv"] = telemetry.vbus_voltage_mv;
  } else {
    output["vbusVoltageMv"] = nullptr;
  }
  if (telemetry.has_input_current) {
    output["inputCurrentMa"] = telemetry.input_current_ma;
  } else {
    output["inputCurrentMa"] = nullptr;
  }
  if (telemetry.has_board_temperature) {
    output["boardTemperatureC"] = telemetry.board_temperature_c;
  } else {
    output["boardTemperatureC"] = nullptr;
  }
}

void write_information(JsonObject output,
                       const DeviceInformation& information) {
  output["model"] = information.model.data();
  output["name"] = information.name.data();
  output["firmwareVersion"] = information.firmware_version.data();
  output["hardwareRevision"] = information.hardware_revision.data();
  output["snapshotSchemaVersion"] = information.snapshot_schema_version;
  output["managementSchemaVersion"] = information.management_schema_version;
  JsonObject capabilities = output["capabilities"].to<JsonObject>();
  capabilities["settings"] = information.supports_settings;
  capabilities["identify"] = information.supports_identify;
  capabilities["restart"] = information.supports_restart;
  capabilities["forget"] = information.supports_forget;
  capabilities["brightness"] = information.supports_brightness;
  capabilities["battery"] = information.supports_battery;
  capabilities["vbusVoltage"] = information.supports_vbus_voltage;
  capabilities["inputCurrent"] = information.supports_input_current;
}

void write_state(JsonObject output, const DeviceState& state) {
  write_information(output["information"].to<JsonObject>(), state.information);
  write_telemetry(output["telemetry"].to<JsonObject>(), state.telemetry);
  write_settings(output["settings"].to<JsonObject>(), state.settings);
}

size_t serialize_bounded(JsonDocument& document, uint8_t* output,
                         size_t output_size) {
  if (output == nullptr || output_size == 0) {
    return 0;
  }
  const size_t required = measureJson(document);
  if (required == 0 || required > output_size ||
      required > kMaximumManagementBytes) {
    return 0;
  }
  return serializeJson(document, output, output_size);
}

}  // namespace

ManagementStatus parse_management_request(const uint8_t* payload,
                                          size_t length,
                                          ManagementRequest& output) {
  if (length > kMaximumManagementBytes) {
    return ManagementStatus::TooLarge;
  }
  if (payload == nullptr || length == 0) {
    return ManagementStatus::InvalidJson;
  }
  JsonDocument document;
  const DeserializationError error = deserializeJson(document, payload, length);
  if (error || !document.is<JsonObject>()) {
    return ManagementStatus::InvalidJson;
  }
  const JsonObjectConst root = document.as<JsonObjectConst>();
  static constexpr const char* kEnvelopeKeys[] = {
      "schemaVersion", "requestId", "type", "payload"};
  if (!has_only_keys(root, kEnvelopeKeys,
                     sizeof(kEnvelopeKeys) / sizeof(kEnvelopeKeys[0])) ||
      !root["schemaVersion"].is<int>()) {
    return ManagementStatus::InvalidRequest;
  }
  if (root["schemaVersion"].as<int>() != kManagementSchemaVersion) {
    return ManagementStatus::UnsupportedSchema;
  }
  if (!root["requestId"].is<uint32_t>() || !root["type"].is<const char*>() ||
      !root["payload"].is<JsonObjectConst>()) {
    return ManagementStatus::InvalidRequest;
  }

  ManagementRequest candidate{};
  candidate.request_id = root["requestId"].as<uint32_t>();
  if (!parse_command(root["type"].as<const char*>(), candidate.command)) {
    return ManagementStatus::UnsupportedCommand;
  }
  const JsonObjectConst request_payload = root["payload"].as<JsonObjectConst>();
  if (candidate.command == ManagementCommand::SettingsPatch) {
    const ManagementStatus patch_status =
        parse_settings_patch(request_payload, candidate.settings_patch);
    if (patch_status != ManagementStatus::Ok) {
      return patch_status;
    }
  } else if (!request_payload.isNull() && request_payload.size() != 0) {
    return ManagementStatus::InvalidRequest;
  }
  output = candidate;
  return ManagementStatus::Ok;
}

size_t encode_management_result(const ManagementResult& result,
                                uint8_t* output, size_t output_size) {
  JsonDocument document;
  document["schemaVersion"] = kManagementSchemaVersion;
  document["requestId"] = result.request_id;
  document["type"] = result_type(result.command);
  document["status"] = status_name(result.status);
  JsonObject payload = document["payload"].to<JsonObject>();
  if (result.has_device_state) {
    switch (result.command) {
      case ManagementCommand::DeviceGet:
        write_state(payload, result.device_state);
        break;
      case ManagementCommand::TelemetryGet:
        write_telemetry(payload, result.device_state.telemetry);
        break;
      case ManagementCommand::SettingsGet:
      case ManagementCommand::SettingsPatch:
        write_settings(payload, result.device_state.settings);
        break;
      case ManagementCommand::DeviceIdentify:
      case ManagementCommand::DeviceRestart:
      case ManagementCommand::DeviceForget:
        break;
    }
  }
  return serialize_bounded(document, output, output_size);
}

size_t encode_device_state_event(const DeviceState& state, uint8_t* output,
                                 size_t output_size) {
  JsonDocument document;
  document["schemaVersion"] = kManagementSchemaVersion;
  document["requestId"] = 0;
  document["type"] = "device.state";
  write_state(document["payload"].to<JsonObject>(), state);
  return serialize_bounded(document, output, output_size);
}

}  // namespace agentmeter
