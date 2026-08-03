#include <array>
#include <cstring>
#include <string>
#include <vector>

#include <ArduinoJson.h>
#include <unity.h>

#include "management_protocol.h"
#include "protocol.h"

namespace {

agentmeter::ManagementStatus parse_request(
    const char* payload, agentmeter::ManagementRequest& request) {
  return agentmeter::parse_management_request(
      reinterpret_cast<const uint8_t*>(payload), std::strlen(payload),
      request);
}

void test_parse_settings_patch_captures_revision_and_fields() {
  constexpr char payload[] =
      R"({"schemaVersion":1,"requestId":17,"type":"settings.patch",)"
      R"("payload":{"baseRevision":8,"alwaysOn":true,"rotationSeconds":5,)"
      R"("hiddenProviderIds":["gemini"],)"
      R"("providerOrder":["claude","codex"]}})";
  agentmeter::ManagementRequest request{};

  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(agentmeter::ManagementStatus::Ok),
      static_cast<uint8_t>(parse_request(payload, request)));
  TEST_ASSERT_EQUAL_UINT32(17, request.request_id);
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(agentmeter::ManagementCommand::SettingsPatch),
      static_cast<uint8_t>(request.command));
  TEST_ASSERT_EQUAL_UINT32(8, request.settings_patch.base_revision);
  TEST_ASSERT_TRUE(request.settings_patch.has_always_on);
  TEST_ASSERT_TRUE(request.settings_patch.always_on);
  TEST_ASSERT_TRUE(request.settings_patch.has_rotation_seconds);
  TEST_ASSERT_EQUAL_UINT8(5, request.settings_patch.rotation_seconds);
  TEST_ASSERT_TRUE(request.settings_patch.has_hidden_provider_ids);
  TEST_ASSERT_TRUE(agentmeter::provider_id_list_contains(
      request.settings_patch.hidden_provider_ids, "gemini"));
  TEST_ASSERT_EQUAL_UINT8(2, request.settings_patch.provider_order.count);
}

void test_parse_accepts_every_supported_empty_payload_command() {
  struct CommandCase {
    const char* type;
    agentmeter::ManagementCommand command;
  };
  constexpr CommandCase cases[] = {
      {"device.get", agentmeter::ManagementCommand::DeviceGet},
      {"telemetry.get", agentmeter::ManagementCommand::TelemetryGet},
      {"settings.get", agentmeter::ManagementCommand::SettingsGet},
      {"device.identify", agentmeter::ManagementCommand::DeviceIdentify},
      {"device.restart", agentmeter::ManagementCommand::DeviceRestart},
      {"device.forget", agentmeter::ManagementCommand::DeviceForget},
  };

  for (const auto& item : cases) {
    const std::string payload =
        std::string("{\"schemaVersion\":1,\"requestId\":9,\"type\":\"") +
        item.type + "\",\"payload\":{}}";
    agentmeter::ManagementRequest request{};
    TEST_ASSERT_EQUAL_UINT8(
        static_cast<uint8_t>(agentmeter::ManagementStatus::Ok),
        static_cast<uint8_t>(agentmeter::parse_management_request(
            reinterpret_cast<const uint8_t*>(payload.data()), payload.size(),
            request)));
    TEST_ASSERT_EQUAL_UINT8(static_cast<uint8_t>(item.command),
                            static_cast<uint8_t>(request.command));
  }
}

void test_parser_rejects_unknown_fields_without_mutating_output() {
  constexpr char payload[] =
      R"({"schemaVersion":1,"requestId":17,"type":"settings.patch",)"
      R"("payload":{"baseRevision":8,"alwaysOn":true,"surprise":1}})";
  agentmeter::ManagementRequest request{};
  request.request_id = 91;

  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(agentmeter::ManagementStatus::InvalidRequest),
      static_cast<uint8_t>(parse_request(payload, request)));
  TEST_ASSERT_EQUAL_UINT32(91, request.request_id);
}

void test_parser_reports_schema_command_and_size_errors() {
  agentmeter::ManagementRequest request{};
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(agentmeter::ManagementStatus::UnsupportedSchema),
      static_cast<uint8_t>(parse_request(
          R"({"schemaVersion":2,"requestId":1,"type":"device.get","payload":{}})",
          request)));
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(agentmeter::ManagementStatus::UnsupportedCommand),
      static_cast<uint8_t>(parse_request(
          R"({"schemaVersion":1,"requestId":1,"type":"device.erase","payload":{}})",
          request)));
  std::array<uint8_t, agentmeter::kMaximumManagementBytes + 1> oversized{};
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(agentmeter::ManagementStatus::TooLarge),
      static_cast<uint8_t>(agentmeter::parse_management_request(
          oversized.data(), oversized.size(), request)));
}

void test_parser_rejects_missing_request_id_and_bad_provider_id() {
  agentmeter::ManagementRequest request{};
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(agentmeter::ManagementStatus::InvalidRequest),
      static_cast<uint8_t>(parse_request(
          R"({"schemaVersion":1,"type":"device.get","payload":{}})",
          request)));
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(agentmeter::ManagementStatus::InvalidRequest),
      static_cast<uint8_t>(parse_request(
          R"({"schemaVersion":1,"requestId":2,"type":"settings.patch","payload":{"baseRevision":1,"hiddenProviderIds":["Claude"]}})",
          request)));
}

void test_management_result_preserves_request_correlation_and_status() {
  agentmeter::ManagementResult result{};
  result.request_id = 17;
  result.command = agentmeter::ManagementCommand::SettingsPatch;
  result.status = agentmeter::ManagementStatus::RevisionConflict;
  std::array<uint8_t, agentmeter::kMaximumManagementBytes> output{};

  const size_t length = agentmeter::encode_management_result(
      result, output.data(), output.size());
  TEST_ASSERT_GREATER_THAN_UINT16(0, length);
  JsonDocument document;
  TEST_ASSERT_FALSE(
      deserializeJson(document, output.data(), length));
  TEST_ASSERT_EQUAL_UINT32(17, document["requestId"].as<uint32_t>());
  TEST_ASSERT_EQUAL_STRING("settings.result", document["type"]);
  TEST_ASSERT_EQUAL_STRING("revisionConflict", document["status"]);
  TEST_ASSERT_TRUE(document["payload"].is<JsonObject>());
}

void test_device_state_encodes_usb_without_fabricating_battery() {
  agentmeter::DeviceState state{};
  std::strcpy(state.information.model.data(), "waveshare-amoled-216");
  std::strcpy(state.information.name.data(), "AgentMeter");
  std::strcpy(state.information.firmware_version.data(), "0.1.0");
  std::strcpy(state.information.hardware_revision.data(), "1");
  state.telemetry.power_source = agentmeter::PowerSource::Usb;
  state.telemetry.usb_present = true;
  state.telemetry.battery_present = false;
  state.telemetry.has_vbus_voltage = true;
  state.telemetry.vbus_voltage_mv = 5012;
  std::array<uint8_t, agentmeter::kMaximumManagementBytes> output{};

  const size_t length = agentmeter::encode_device_state_event(
      state, output.data(), output.size());
  JsonDocument document;
  TEST_ASSERT_FALSE(deserializeJson(document, output.data(), length));
  TEST_ASSERT_EQUAL_STRING("usb",
                           document["payload"]["telemetry"]["powerSource"]);
  TEST_ASSERT_FALSE(
      document["payload"]["telemetry"]["batteryPresent"].as<bool>());
  TEST_ASSERT_TRUE(
      document["payload"]["telemetry"]["batteryPercent"].isNull());
  TEST_ASSERT_TRUE(
      document["payload"]["telemetry"]["inputCurrentMa"].isNull());
  TEST_ASSERT_EQUAL_UINT16(
      5012, document["payload"]["telemetry"]["vbusVoltageMv"].as<uint16_t>());
}

void test_device_state_encodes_available_battery_measurements() {
  agentmeter::DeviceState state{};
  std::strcpy(state.information.model.data(), "waveshare-amoled-216");
  std::strcpy(state.information.name.data(), "AgentMeter");
  std::strcpy(state.information.firmware_version.data(), "0.1.0");
  std::strcpy(state.information.hardware_revision.data(), "1");
  state.telemetry.power_source = agentmeter::PowerSource::Battery;
  state.telemetry.battery_present = true;
  state.telemetry.has_charging = true;
  state.telemetry.charging = false;
  state.telemetry.has_battery_voltage = true;
  state.telemetry.battery_voltage_mv = 4018;
  state.telemetry.has_battery_percent = true;
  state.telemetry.battery_percent = 72;
  std::array<uint8_t, agentmeter::kMaximumManagementBytes> output{};

  const size_t length = agentmeter::encode_device_state_event(
      state, output.data(), output.size());
  JsonDocument document;
  TEST_ASSERT_FALSE(deserializeJson(document, output.data(), length));
  TEST_ASSERT_EQUAL_STRING(
      "battery", document["payload"]["telemetry"]["powerSource"]);
  TEST_ASSERT_EQUAL_UINT8(
      72, document["payload"]["telemetry"]["batteryPercent"].as<uint8_t>());
  TEST_ASSERT_EQUAL_UINT16(
      4018,
      document["payload"]["telemetry"]["batteryVoltageMv"].as<uint16_t>());
  TEST_ASSERT_FALSE(document["payload"]["telemetry"]["charging"].as<bool>());
}

std::vector<uint8_t> management_frame(uint16_t message_id, uint16_t total,
                                      uint16_t offset, const uint8_t* payload,
                                      size_t length) {
  std::vector<uint8_t> output{
      agentmeter::kProtocolVersion,
      agentmeter::kManagementRequestMessageType,
      static_cast<uint8_t>(message_id),
      static_cast<uint8_t>(message_id >> 8U),
      static_cast<uint8_t>(total),
      static_cast<uint8_t>(total >> 8U),
      static_cast<uint8_t>(offset),
      static_cast<uint8_t>(offset >> 8U),
  };
  output.insert(output.end(), payload, payload + length);
  return output;
}

void test_management_reassembler_returns_correlated_payload() {
  constexpr char payload[] =
      R"({"schemaVersion":1,"requestId":17,"type":"device.get","payload":{}})";
  constexpr uint16_t total = sizeof(payload) - 1;
  constexpr uint16_t split = total / 2;
  const auto first = management_frame(
      17, total, 0, reinterpret_cast<const uint8_t*>(payload), split);
  const auto second = management_frame(
      17, total, split, reinterpret_cast<const uint8_t*>(payload) + split,
      total - split);
  agentmeter::FragmentReassembler reassembler(
      agentmeter::kManagementRequestMessageType,
      agentmeter::kMaximumManagementBytes);
  agentmeter::ReassembledFrame complete{};

  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(agentmeter::FrameStatus::Incomplete),
      static_cast<uint8_t>(
          reassembler.push(first.data(), first.size(), 1000, complete)));
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(agentmeter::FrameStatus::Ok),
      static_cast<uint8_t>(
          reassembler.push(second.data(), second.size(), 1100, complete)));
  TEST_ASSERT_EQUAL_UINT16(17, complete.message_id);
  TEST_ASSERT_EQUAL_UINT16(total, complete.length);
  TEST_ASSERT_EQUAL_UINT8(agentmeter::kManagementRequestMessageType,
                          complete.message_type);
  TEST_ASSERT_NOT_NULL(complete.payload);
  TEST_ASSERT_EQUAL_UINT8_ARRAY(payload, complete.payload, total);
}

void test_management_reassembler_rejects_out_of_order_fragment() {
  constexpr uint8_t payload[] = {'{', '}'};
  const auto second = management_frame(8, 2, 1, payload + 1, 1);
  agentmeter::FragmentReassembler reassembler(
      agentmeter::kManagementRequestMessageType,
      agentmeter::kMaximumManagementBytes);
  agentmeter::ReassembledFrame complete{};

  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(agentmeter::FrameStatus::MalformedFrame),
      static_cast<uint8_t>(
          reassembler.push(second.data(), second.size(), 1000, complete)));
}

}  // namespace

void run_management_protocol_tests() {
  RUN_TEST(test_parse_settings_patch_captures_revision_and_fields);
  RUN_TEST(test_parse_accepts_every_supported_empty_payload_command);
  RUN_TEST(test_parser_rejects_unknown_fields_without_mutating_output);
  RUN_TEST(test_parser_reports_schema_command_and_size_errors);
  RUN_TEST(test_parser_rejects_missing_request_id_and_bad_provider_id);
  RUN_TEST(test_management_result_preserves_request_correlation_and_status);
  RUN_TEST(test_device_state_encodes_usb_without_fabricating_battery);
  RUN_TEST(test_device_state_encodes_available_battery_measurements);
  RUN_TEST(test_management_reassembler_returns_correlated_payload);
  RUN_TEST(test_management_reassembler_rejects_out_of_order_fragment);
}
