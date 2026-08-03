#include <array>
#include <cstring>

#include <ArduinoJson.h>
#include <unity.h>

#include "device_controller.h"

namespace {

class RecordingSettingsStore final : public agentmeter::SettingsRepository {
 public:
  agentmeter::SettingsLoadResult load(agentmeter::DeviceSettings& output) override {
    output = loaded;
    return load_result;
  }

  bool save(const agentmeter::DeviceSettings& settings) override {
    ++save_count;
    saved = settings;
    return save_succeeds;
  }

  agentmeter::DeviceSettings loaded{};
  agentmeter::DeviceSettings saved{};
  agentmeter::SettingsLoadResult load_result =
      agentmeter::SettingsLoadResult::Loaded;
  uint32_t save_count = 0;
  bool save_succeeds = true;
};

class RecordingEventSink final : public agentmeter::ManagementEventSink {
 public:
  bool publish(uint8_t message_type, uint16_t message_id,
               const uint8_t* payload, size_t length) override {
    ++publish_count;
    last_message_type = message_type;
    last_message_id = message_id;
    last_length = length;
    if (payload != nullptr && length <= last_payload.size()) {
      std::memcpy(last_payload.data(), payload, length);
    }
    return publish_succeeds;
  }

  JsonDocument document() const {
    JsonDocument result;
    deserializeJson(result, last_payload.data(), last_length);
    return result;
  }

  std::array<uint8_t, agentmeter::kMaximumManagementBytes> last_payload{};
  size_t last_length = 0;
  uint32_t publish_count = 0;
  uint16_t last_message_id = 0;
  uint8_t last_message_type = 0;
  bool publish_succeeds = true;
};

class RecordingPlatform final : public agentmeter::DevicePlatform {
 public:
  agentmeter::DeviceInformation information() override {
    agentmeter::DeviceInformation value{};
    std::strcpy(value.model.data(), "waveshare-amoled-216");
    std::strcpy(value.name.data(), "AgentMeter");
    std::strcpy(value.firmware_version.data(), "0.1.0");
    std::strcpy(value.hardware_revision.data(), "1");
    return value;
  }

  agentmeter::DeviceTelemetry telemetry(
      const agentmeter::DeviceSettings& settings) override {
    agentmeter::DeviceTelemetry value{};
    value.brightness_percent = settings.brightness_percent;
    value.power_source = agentmeter::PowerSource::Usb;
    value.usb_present = true;
    return value;
  }

  void apply_settings(const agentmeter::DeviceSettings& settings) override {
    ++apply_count;
    applied = settings;
  }

  void identify() override { ++identify_count; }
  void restart() override { ++restart_count; }
  void forget_bonds() override { ++forget_count; }

  agentmeter::DeviceSettings applied{};
  uint32_t apply_count = 0;
  uint32_t identify_count = 0;
  uint32_t restart_count = 0;
  uint32_t forget_count = 0;
};

agentmeter::ManagementRequest make_always_on_patch(uint32_t request_id,
                                                   uint32_t base_revision,
                                                   bool value) {
  agentmeter::ManagementRequest request{};
  request.request_id = request_id;
  request.command = agentmeter::ManagementCommand::SettingsPatch;
  request.settings_patch.base_revision = base_revision;
  request.settings_patch.has_always_on = true;
  request.settings_patch.always_on = value;
  return request;
}

void test_controller_confirms_patch_only_after_persistence() {
  RecordingSettingsStore store;
  store.loaded.revision = 8;
  RecordingEventSink events;
  RecordingPlatform platform;
  agentmeter::DeviceController controller(store, events, platform);
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(agentmeter::SettingsLoadResult::Loaded),
      static_cast<uint8_t>(controller.begin()));

  controller.handle(make_always_on_patch(17, 8, true), 1000);

  TEST_ASSERT_EQUAL_UINT32(9, store.saved.revision);
  TEST_ASSERT_TRUE(store.saved.always_on);
  TEST_ASSERT_EQUAL_UINT32(9, controller.settings().revision);
  TEST_ASSERT_TRUE(controller.settings().always_on);
  TEST_ASSERT_EQUAL_UINT32(2, platform.apply_count);
  const JsonDocument result = events.document();
  TEST_ASSERT_EQUAL_STRING("settings.result", result["type"]);
  TEST_ASSERT_EQUAL_STRING("ok", result["status"]);
  TEST_ASSERT_EQUAL_UINT32(9, result["payload"]["revision"].as<uint32_t>());
}

void test_controller_rejects_stale_revision_without_saving() {
  RecordingSettingsStore store;
  store.loaded.revision = 9;
  RecordingEventSink events;
  RecordingPlatform platform;
  agentmeter::DeviceController controller(store, events, platform);
  controller.begin();

  controller.handle(make_always_on_patch(18, 8, true), 1000);

  TEST_ASSERT_EQUAL_UINT32(0, store.save_count);
  TEST_ASSERT_FALSE(controller.settings().always_on);
  const JsonDocument result = events.document();
  TEST_ASSERT_EQUAL_STRING("revisionConflict", result["status"]);
  TEST_ASSERT_EQUAL_UINT32(9, result["payload"]["revision"].as<uint32_t>());
}

void test_persistence_failure_never_applies_candidate() {
  RecordingSettingsStore store;
  store.loaded.revision = 3;
  store.save_succeeds = false;
  RecordingEventSink events;
  RecordingPlatform platform;
  agentmeter::DeviceController controller(store, events, platform);
  controller.begin();

  controller.handle(make_always_on_patch(19, 3, true), 1000);

  TEST_ASSERT_EQUAL_UINT32(1, store.save_count);
  TEST_ASSERT_FALSE(controller.settings().always_on);
  TEST_ASSERT_EQUAL_UINT32(1, platform.apply_count);
  TEST_ASSERT_EQUAL_STRING("persistenceFailed",
                           events.document()["status"].as<const char*>());
}

void test_unchanged_settings_do_not_write_flash() {
  RecordingSettingsStore store;
  store.loaded.revision = 4;
  RecordingEventSink events;
  RecordingPlatform platform;
  agentmeter::DeviceController controller(store, events, platform);
  controller.begin();

  controller.handle(make_always_on_patch(20, 4, false), 1000);

  TEST_ASSERT_EQUAL_UINT32(0, store.save_count);
  TEST_ASSERT_EQUAL_UINT32(4, controller.settings().revision);
  TEST_ASSERT_EQUAL_STRING("ok", events.document()["status"].as<const char*>());
}

void test_touchscreen_change_uses_same_revisioned_path() {
  RecordingSettingsStore store;
  store.loaded.revision = 6;
  RecordingEventSink events;
  RecordingPlatform platform;
  agentmeter::DeviceController controller(store, events, platform);
  controller.begin();
  agentmeter::DeviceSettings candidate = controller.settings();
  candidate.full_view = true;

  controller.settings_changed_from_ui(candidate, 1000);

  TEST_ASSERT_EQUAL_UINT32(1, store.save_count);
  TEST_ASSERT_EQUAL_UINT32(7, store.saved.revision);
  TEST_ASSERT_TRUE(controller.settings().full_view);
  TEST_ASSERT_EQUAL_UINT8(agentmeter::kDeviceEventMessageType,
                          events.last_message_type);
  TEST_ASSERT_EQUAL_STRING("device.state",
                           events.document()["type"].as<const char*>());
}

void test_restart_and_forget_run_only_after_result_is_queued() {
  RecordingSettingsStore store;
  RecordingEventSink events;
  RecordingPlatform platform;
  agentmeter::DeviceController controller(store, events, platform);
  controller.begin();
  agentmeter::ManagementRequest restart{};
  restart.request_id = 21;
  restart.command = agentmeter::ManagementCommand::DeviceRestart;

  controller.handle(restart, 1000);
  TEST_ASSERT_EQUAL_UINT32(0, platform.restart_count);
  controller.tick(1001);
  TEST_ASSERT_EQUAL_UINT32(0, platform.restart_count);
  controller.tick(1250);
  TEST_ASSERT_EQUAL_UINT32(1, platform.restart_count);

  agentmeter::ManagementRequest forget{};
  forget.request_id = 22;
  forget.command = agentmeter::ManagementCommand::DeviceForget;
  controller.handle(forget, 2000);
  controller.tick(2250);
  TEST_ASSERT_EQUAL_UINT32(1, platform.forget_count);

  events.publish_succeeds = false;
  forget.request_id = 23;
  controller.handle(forget, 3000);
  controller.tick(3250);
  TEST_ASSERT_EQUAL_UINT32(1, platform.forget_count);
}

void test_identify_does_not_persist_settings() {
  RecordingSettingsStore store;
  RecordingEventSink events;
  RecordingPlatform platform;
  agentmeter::DeviceController controller(store, events, platform);
  controller.begin();
  agentmeter::ManagementRequest identify{};
  identify.request_id = 23;
  identify.command = agentmeter::ManagementCommand::DeviceIdentify;

  controller.handle(identify, 1000);

  TEST_ASSERT_EQUAL_UINT32(0, store.save_count);
  TEST_ASSERT_EQUAL_UINT32(1, platform.identify_count);
}

}  // namespace

void run_device_controller_tests() {
  RUN_TEST(test_controller_confirms_patch_only_after_persistence);
  RUN_TEST(test_controller_rejects_stale_revision_without_saving);
  RUN_TEST(test_persistence_failure_never_applies_candidate);
  RUN_TEST(test_unchanged_settings_do_not_write_flash);
  RUN_TEST(test_touchscreen_change_uses_same_revisioned_path);
  RUN_TEST(test_restart_and_forget_run_only_after_result_is_queued);
  RUN_TEST(test_identify_does_not_persist_settings);
}
