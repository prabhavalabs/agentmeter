#include "settings_store.h"

#include <Preferences.h>

namespace agentmeter {
namespace {

constexpr char kNamespace[] = "agentmeter";
constexpr char kAlwaysOnKey[] = "alwaysOn";
constexpr char kFullViewKey[] = "fullView";
constexpr char kRotationKey[] = "rotateSec";
constexpr char kHiddenKey[] = "hidden";
constexpr char kSettingsV1Key[] = "settingsV1";

}  // namespace

SettingsLoadResult load_device_settings(DeviceSettings& settings) {
  Preferences storage;
  if (!storage.begin(kNamespace, false)) {
    return SettingsLoadResult::StorageError;
  }

  const size_t blob_length = storage.getBytesLength(kSettingsV1Key);
  if (blob_length > 0) {
    DeviceSettings loaded{};
    SettingsBlob blob{};
    if (blob_length > blob.bytes.size() ||
        storage.getBytes(kSettingsV1Key, blob.bytes.data(), blob_length) !=
            blob_length) {
      storage.end();
      return SettingsLoadResult::StorageError;
    }
    storage.end();
    if (decode_settings_blob(blob.bytes.data(), blob_length, loaded) !=
        SettingsDecodeStatus::Ok) {
      settings = DeviceSettings{};
      return SettingsLoadResult::Defaults;
    }
    settings = loaded;
    return SettingsLoadResult::Loaded;
  }

  const bool has_legacy = storage.isKey(kAlwaysOnKey) ||
                          storage.isKey(kFullViewKey) ||
                          storage.isKey(kRotationKey) ||
                          storage.isKey(kHiddenKey);
  if (!has_legacy) {
    storage.end();
    settings = DeviceSettings{};
    return SettingsLoadResult::Defaults;
  }

  LegacySettings legacy{};
  legacy.always_on = storage.getBool(kAlwaysOnKey, false);
  legacy.full_view = storage.getBool(kFullViewKey, false);
  legacy.rotation_seconds =
      storage.getUChar(kRotationKey, kMinimumRotationSeconds);
  const String hidden = storage.getString(kHiddenKey, "");
  DeviceSettings hidden_settings{};
  if (!decode_hidden_provider_ids(hidden.c_str(), hidden_settings)) {
    storage.end();
    settings = DeviceSettings{};
    return SettingsLoadResult::Defaults;
  }
  legacy.hidden_provider_ids = hidden_settings.hidden_provider_ids;

  DeviceSettings migrated{};
  SettingsBlob blob{};
  if (!migrate_legacy_settings(legacy, migrated) ||
      !encode_settings_blob(migrated, blob)) {
    storage.end();
    settings = DeviceSettings{};
    return SettingsLoadResult::Defaults;
  }
  const bool saved = storage.putBytes(kSettingsV1Key, blob.bytes.data(),
                                      blob.length) == blob.length;
  storage.end();
  settings = migrated;
  return saved ? SettingsLoadResult::Migrated
               : SettingsLoadResult::StorageError;
}

bool save_device_settings(const DeviceSettings& settings) {
  SettingsBlob blob{};
  if (!encode_settings_blob(settings, blob)) {
    return false;
  }
  Preferences storage;
  if (!storage.begin(kNamespace, false)) {
    return false;
  }
  const bool saved = storage.putBytes(kSettingsV1Key, blob.bytes.data(),
                                      blob.length) == blob.length;
  storage.end();
  return saved;
}

void load_dashboard_preferences(DashboardPreferences& preferences) {
  load_device_settings(preferences);
}

bool save_dashboard_preferences(const DashboardPreferences& preferences) {
  return save_device_settings(preferences);
}

}  // namespace agentmeter
