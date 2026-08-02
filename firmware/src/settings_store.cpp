#include "settings_store.h"

#include <Preferences.h>

#include <array>
#include <cstring>

namespace agentmeter {
namespace {

constexpr char kNamespace[] = "agentmeter";
constexpr char kAlwaysOnKey[] = "alwaysOn";
constexpr char kFullViewKey[] = "fullView";
constexpr char kRotationKey[] = "rotateSec";
constexpr char kHiddenKey[] = "hidden";

}  // namespace

void load_dashboard_preferences(DashboardPreferences& preferences) {
  Preferences storage;
  if (!storage.begin(kNamespace, false)) {
    return;
  }
  DashboardPreferences loaded{};
  loaded.always_on = storage.getBool(kAlwaysOnKey, false);
  loaded.full_view = storage.getBool(kFullViewKey, false);
  set_rotation_seconds(
      loaded, storage.getUChar(kRotationKey, kMinimumRotationSeconds));
  const String hidden = storage.getString(kHiddenKey, "");
  decode_hidden_provider_ids(hidden.c_str(), loaded);
  storage.end();
  preferences = loaded;
}

bool save_dashboard_preferences(const DashboardPreferences& preferences) {
  std::array<char, 256> hidden{};
  if (!encode_hidden_provider_ids(preferences, hidden.data(), hidden.size())) {
    return false;
  }
  Preferences storage;
  if (!storage.begin(kNamespace, false)) {
    return false;
  }
  const bool saved =
      storage.putBool(kAlwaysOnKey, preferences.always_on) == 1 &&
      storage.putBool(kFullViewKey, preferences.full_view) == 1 &&
      storage.putUChar(kRotationKey, preferences.rotation_seconds) == 1 &&
      storage.putString(kHiddenKey, hidden.data()) == std::strlen(hidden.data());
  storage.end();
  return saved;
}

}  // namespace agentmeter
