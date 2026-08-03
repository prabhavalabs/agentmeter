#include <array>
#include <cstring>

#include <unity.h>

#include "management_model.h"

namespace {

agentmeter::DashboardSnapshot make_snapshot(const char* first,
                                            const char* second = nullptr,
                                            const char* third = nullptr) {
  agentmeter::DashboardSnapshot snapshot{};
  const char* ids[] = {first, second, third};
  for (const char* id : ids) {
    if (id == nullptr) {
      continue;
    }
    std::strcpy(snapshot.providers[snapshot.provider_count].id.data(), id);
    ++snapshot.provider_count;
  }
  return snapshot;
}

void test_device_settings_defaults_are_valid() {
  const agentmeter::DeviceSettings settings{};

  TEST_ASSERT_TRUE(agentmeter::validate_device_settings(settings, nullptr));
  TEST_ASSERT_EQUAL_UINT8(3, settings.rotation_seconds);
  TEST_ASSERT_EQUAL_UINT8(55, settings.brightness_percent);
  TEST_ASSERT_EQUAL_UINT32(300, settings.dim_after_seconds);
  TEST_ASSERT_EQUAL_UINT32(1800, settings.screen_off_after_seconds);
  TEST_ASSERT_EQUAL_UINT8(2, settings.alert_threshold_count);
  TEST_ASSERT_EQUAL_UINT8(75, settings.alert_thresholds[0]);
  TEST_ASSERT_EQUAL_UINT8(90, settings.alert_thresholds[1]);
}

void test_settings_patch_is_selective_and_preserves_revision() {
  agentmeter::DeviceSettings current{};
  current.revision = 8;
  agentmeter::SettingsPatch patch{};
  patch.has_always_on = true;
  patch.always_on = true;

  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(agentmeter::ManagementStatus::Ok),
      static_cast<uint8_t>(
          agentmeter::apply_settings_patch(patch, nullptr, current)));
  TEST_ASSERT_TRUE(current.always_on);
  TEST_ASSERT_FALSE(current.full_view);
  TEST_ASSERT_EQUAL_UINT8(55, current.brightness_percent);
  TEST_ASSERT_EQUAL_UINT32(8, current.revision);
}

void test_ordered_visible_providers_appends_unknown_ids() {
  const agentmeter::DashboardSnapshot snapshot =
      make_snapshot("codex", "claude", "cursor");
  agentmeter::DeviceSettings settings{};
  const char* order[] = {"claude", "codex"};
  TEST_ASSERT_TRUE(agentmeter::set_provider_order(settings, order, 2));
  std::array<uint8_t, agentmeter::kMaximumProviders> indices{};

  TEST_ASSERT_EQUAL_UINT8(
      3, agentmeter::ordered_visible_provider_indices(snapshot, settings,
                                                       indices));
  TEST_ASSERT_EQUAL_UINT8(1, indices[0]);
  TEST_ASSERT_EQUAL_UINT8(0, indices[1]);
  TEST_ASSERT_EQUAL_UINT8(2, indices[2]);
}

void test_hidden_providers_are_removed_from_ordered_results() {
  const agentmeter::DashboardSnapshot snapshot =
      make_snapshot("codex", "claude", "gemini");
  agentmeter::DeviceSettings settings{};
  settings.hidden_provider_ids.count = 1;
  std::strcpy(settings.hidden_provider_ids.values[0].data(), "claude");
  const char* order[] = {"gemini", "claude", "codex"};
  TEST_ASSERT_TRUE(agentmeter::set_provider_order(settings, order, 3));
  std::array<uint8_t, agentmeter::kMaximumProviders> indices{};

  TEST_ASSERT_EQUAL_UINT8(
      2, agentmeter::ordered_visible_provider_indices(snapshot, settings,
                                                       indices));
  TEST_ASSERT_EQUAL_UINT8(2, indices[0]);
  TEST_ASSERT_EQUAL_UINT8(0, indices[1]);
}

void test_validation_rejects_invalid_ranges_and_thresholds() {
  agentmeter::DeviceSettings settings{};

  settings.rotation_seconds = 2;
  TEST_ASSERT_FALSE(agentmeter::validate_device_settings(settings, nullptr));
  settings.rotation_seconds = 3;
  settings.brightness_percent = 0;
  TEST_ASSERT_FALSE(agentmeter::validate_device_settings(settings, nullptr));
  settings.brightness_percent = 55;
  settings.dim_after_seconds = 29;
  TEST_ASSERT_FALSE(agentmeter::validate_device_settings(settings, nullptr));
  settings.dim_after_seconds = 300;
  settings.screen_off_after_seconds = 299;
  TEST_ASSERT_FALSE(agentmeter::validate_device_settings(settings, nullptr));
  settings.screen_off_after_seconds = 1800;
  settings.alert_thresholds = {75, 75, 0};
  TEST_ASSERT_FALSE(agentmeter::validate_device_settings(settings, nullptr));
}

void test_validation_rejects_duplicate_or_malformed_provider_ids() {
  agentmeter::DeviceSettings settings{};
  settings.provider_order.count = 2;
  std::strcpy(settings.provider_order.values[0].data(), "codex");
  std::strcpy(settings.provider_order.values[1].data(), "codex");
  TEST_ASSERT_FALSE(agentmeter::validate_device_settings(settings, nullptr));

  settings.provider_order.count = 1;
  std::strcpy(settings.provider_order.values[0].data(), "Claude");
  TEST_ASSERT_FALSE(agentmeter::validate_device_settings(settings, nullptr));
}

void test_validation_requires_one_visible_provider_for_current_snapshot() {
  const agentmeter::DashboardSnapshot snapshot =
      make_snapshot("codex", "claude");
  agentmeter::DeviceSettings settings{};
  settings.hidden_provider_ids.count = 2;
  std::strcpy(settings.hidden_provider_ids.values[0].data(), "codex");
  std::strcpy(settings.hidden_provider_ids.values[1].data(), "claude");

  TEST_ASSERT_FALSE(agentmeter::validate_device_settings(settings, &snapshot));
  TEST_ASSERT_TRUE(agentmeter::validate_device_settings(settings, nullptr));
}

void test_invalid_patch_does_not_change_confirmed_settings() {
  agentmeter::DeviceSettings current{};
  current.revision = 12;
  agentmeter::SettingsPatch patch{};
  patch.has_rotation_seconds = true;
  patch.rotation_seconds = 61;

  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(agentmeter::ManagementStatus::InvalidRequest),
      static_cast<uint8_t>(
          agentmeter::apply_settings_patch(patch, nullptr, current)));
  TEST_ASSERT_EQUAL_UINT8(3, current.rotation_seconds);
  TEST_ASSERT_EQUAL_UINT32(12, current.revision);
}

}  // namespace

void run_management_model_tests() {
  RUN_TEST(test_device_settings_defaults_are_valid);
  RUN_TEST(test_settings_patch_is_selective_and_preserves_revision);
  RUN_TEST(test_ordered_visible_providers_appends_unknown_ids);
  RUN_TEST(test_hidden_providers_are_removed_from_ordered_results);
  RUN_TEST(test_validation_rejects_invalid_ranges_and_thresholds);
  RUN_TEST(test_validation_rejects_duplicate_or_malformed_provider_ids);
  RUN_TEST(test_validation_requires_one_visible_provider_for_current_snapshot);
  RUN_TEST(test_invalid_patch_does_not_change_confirmed_settings);
}
