#include <cstring>

#include <unity.h>

#include "management_model.h"
#include "settings_codec.h"

namespace {

void test_settings_blob_round_trip_preserves_revision_and_order() {
  agentmeter::DeviceSettings input{};
  input.revision = 42;
  input.always_on = true;
  input.full_view = true;
  input.rotation_seconds = 7;
  input.brightness_percent = 63;
  input.dim_after_seconds = 240;
  input.screen_off_after_seconds = 1200;
  input.alert_thresholds = {70, 85, 98};
  input.alert_threshold_count = 3;
  input.sound_enabled = true;
  input.hidden_provider_ids.count = 1;
  std::strcpy(input.hidden_provider_ids.values[0].data(), "gemini");
  const char* order[] = {"claude", "codex", "cursor"};
  TEST_ASSERT_TRUE(agentmeter::set_provider_order(input, order, 3));
  agentmeter::SettingsBlob blob{};
  agentmeter::DeviceSettings decoded{};

  TEST_ASSERT_TRUE(agentmeter::encode_settings_blob(input, blob));
  TEST_ASSERT_LESS_OR_EQUAL_UINT16(512, blob.length);
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(agentmeter::SettingsDecodeStatus::Ok),
      static_cast<uint8_t>(agentmeter::decode_settings_blob(
          blob.bytes.data(), blob.length, decoded)));
  TEST_ASSERT_TRUE(agentmeter::device_settings_equal(input, decoded));
}

void test_settings_blob_rejects_changed_crc_without_mutating_output() {
  const agentmeter::DeviceSettings original{};
  agentmeter::SettingsBlob blob{};
  TEST_ASSERT_TRUE(agentmeter::encode_settings_blob(original, blob));
  blob.bytes[blob.length - 1] ^= 0xFF;
  agentmeter::DeviceSettings output{};
  output.revision = 99;

  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(
          agentmeter::SettingsDecodeStatus::InvalidChecksum),
      static_cast<uint8_t>(agentmeter::decode_settings_blob(
          blob.bytes.data(), blob.length, output)));
  TEST_ASSERT_EQUAL_UINT32(99, output.revision);
}

void test_settings_blob_rejects_truncation_without_mutating_output() {
  const agentmeter::DeviceSettings original{};
  agentmeter::SettingsBlob blob{};
  TEST_ASSERT_TRUE(agentmeter::encode_settings_blob(original, blob));
  agentmeter::DeviceSettings output{};
  output.revision = 77;

  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(agentmeter::SettingsDecodeStatus::Malformed),
      static_cast<uint8_t>(agentmeter::decode_settings_blob(
          blob.bytes.data(), blob.length - 6, output)));
  TEST_ASSERT_EQUAL_UINT32(77, output.revision);
}

void test_settings_blob_rejects_invalid_model_before_encoding() {
  agentmeter::DeviceSettings invalid{};
  invalid.brightness_percent = 0;
  agentmeter::SettingsBlob blob{};

  TEST_ASSERT_FALSE(agentmeter::encode_settings_blob(invalid, blob));
  TEST_ASSERT_EQUAL_UINT16(0, blob.length);
}

void test_legacy_settings_migrate_to_revisioned_defaults() {
  agentmeter::LegacySettings legacy{};
  legacy.always_on = true;
  legacy.full_view = true;
  legacy.rotation_seconds = 9;
  legacy.hidden_provider_ids.count = 1;
  std::strcpy(legacy.hidden_provider_ids.values[0].data(), "gemini");
  agentmeter::DeviceSettings migrated{};

  TEST_ASSERT_TRUE(agentmeter::migrate_legacy_settings(legacy, migrated));
  TEST_ASSERT_EQUAL_UINT32(1, migrated.revision);
  TEST_ASSERT_TRUE(migrated.always_on);
  TEST_ASSERT_TRUE(migrated.full_view);
  TEST_ASSERT_EQUAL_UINT8(9, migrated.rotation_seconds);
  TEST_ASSERT_EQUAL_UINT8(55, migrated.brightness_percent);
  TEST_ASSERT_TRUE(agentmeter::provider_id_list_contains(
      migrated.hidden_provider_ids, "gemini"));
}

void test_invalid_legacy_settings_do_not_mutate_output() {
  agentmeter::LegacySettings legacy{};
  legacy.rotation_seconds = 2;
  agentmeter::DeviceSettings output{};
  output.revision = 91;

  TEST_ASSERT_FALSE(agentmeter::migrate_legacy_settings(legacy, output));
  TEST_ASSERT_EQUAL_UINT32(91, output.revision);
}

}  // namespace

void run_settings_codec_tests() {
  RUN_TEST(test_settings_blob_round_trip_preserves_revision_and_order);
  RUN_TEST(test_settings_blob_rejects_changed_crc_without_mutating_output);
  RUN_TEST(test_settings_blob_rejects_truncation_without_mutating_output);
  RUN_TEST(test_settings_blob_rejects_invalid_model_before_encoding);
  RUN_TEST(test_legacy_settings_migrate_to_revisioned_defaults);
  RUN_TEST(test_invalid_legacy_settings_do_not_mutate_output);
}
