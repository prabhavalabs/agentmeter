#include <cstring>
#include <vector>

#include <unity.h>

#include "dashboard_model.h"
#include "protocol.h"
#include "ui_format.h"

namespace {

constexpr char kValidSnapshot[] = R"json({
  "schemaVersion": 1,
  "messageId": 42,
  "generatedAtEpoch": 1785508800,
  "staleAfterSeconds": 180,
  "providers": [{
    "id": "codex",
    "name": "Codex",
    "status": "ok",
    "windows": [{
      "kind": "session",
      "label": "Session",
      "usedPercent": 28,
      "resetAtEpoch": 1785527700
    }]
  }],
  "display": {
    "brightnessPercent": 55,
    "dimAfterSeconds": 300,
    "screenOffAfterSeconds": 1800,
    "alertThresholds": [75, 90],
    "soundEnabled": false
  },
  "event": {
    "id": "threshold:claude:weekly:90",
    "kind": "threshold",
    "level": "critical",
    "expiresAtEpoch": 1785508890
  }
})json";

void test_parse_snapshot_populates_bounded_display_model() {
  agentmeter::DashboardSnapshot snapshot{};

  const auto status = agentmeter::parse_snapshot(
      reinterpret_cast<const uint8_t*>(kValidSnapshot),
      std::strlen(kValidSnapshot), snapshot);

  TEST_ASSERT_EQUAL(static_cast<int>(agentmeter::ParseStatus::Ok),
                    static_cast<int>(status));
  TEST_ASSERT_EQUAL_UINT16(42, snapshot.message_id);
  TEST_ASSERT_EQUAL_UINT8(1, snapshot.provider_count);
  TEST_ASSERT_EQUAL_STRING("codex", snapshot.providers[0].id.data());
  TEST_ASSERT_EQUAL_INT16(28,
                          snapshot.providers[0].windows[0].used_percent);
  TEST_ASSERT_EQUAL_UINT32(300, snapshot.display.dim_after_seconds);
  TEST_ASSERT_TRUE(snapshot.event.present);
  TEST_ASSERT_EQUAL_STRING("threshold:claude:weekly:90",
                           snapshot.event.id.data());
  TEST_ASSERT_EQUAL(static_cast<int>(agentmeter::EventLevel::Critical),
                    static_cast<int>(snapshot.event.level));
}

void test_countdown_and_staleness_use_rollover_safe_monotonic_time() {
  agentmeter::DashboardSnapshot snapshot{};
  snapshot.generated_at_epoch = 1000;
  snapshot.stale_after_seconds = 3;
  constexpr uint32_t received_at_ms = 0xFFFFFF00U;

  const int64_t now_epoch =
      agentmeter::estimated_epoch(snapshot, received_at_ms, 0x00000AB8U);

  TEST_ASSERT_EQUAL_INT64(1003, now_epoch);
  TEST_ASSERT_EQUAL_INT64(2, agentmeter::seconds_until_reset(1005, now_epoch));
  TEST_ASSERT_EQUAL_INT64(0, agentmeter::seconds_until_reset(1002, now_epoch));
  TEST_ASSERT_FALSE(agentmeter::is_stale(snapshot, received_at_ms, 0x00000AB8U));
  TEST_ASSERT_TRUE(agentmeter::is_stale(snapshot, received_at_ms, 0x00000EA0U));
}

std::vector<uint8_t> frame(uint16_t message_id, uint16_t total,
                           uint16_t offset, const uint8_t* payload,
                           size_t length) {
  std::vector<uint8_t> output{
      1,
      1,
      static_cast<uint8_t>(message_id & 0xFF),
      static_cast<uint8_t>(message_id >> 8),
      static_cast<uint8_t>(total & 0xFF),
      static_cast<uint8_t>(total >> 8),
      static_cast<uint8_t>(offset & 0xFF),
      static_cast<uint8_t>(offset >> 8),
  };
  output.insert(output.end(), payload, payload + length);
  return output;
}

void test_reassembler_applies_snapshot_only_after_final_in_order_fragment() {
  const auto* payload = reinterpret_cast<const uint8_t*>(kValidSnapshot);
  const auto total = static_cast<uint16_t>(std::strlen(kValidSnapshot));
  const uint16_t split = total / 2;
  const auto first = frame(42, total, 0, payload, split);
  const auto second = frame(42, total, split, payload + split, total - split);
  agentmeter::DashboardSnapshot snapshot{};
  agentmeter::Reassembler reassembler;

  TEST_ASSERT_EQUAL(
      static_cast<int>(agentmeter::FrameStatus::Incomplete),
      static_cast<int>(
          reassembler.push(first.data(), first.size(), 1000, snapshot)));
  TEST_ASSERT_EQUAL_UINT8(0, snapshot.provider_count);
  TEST_ASSERT_EQUAL(
      static_cast<int>(agentmeter::FrameStatus::Ok),
      static_cast<int>(
          reassembler.push(second.data(), second.size(), 1100, snapshot)));
  TEST_ASSERT_EQUAL_UINT16(42, snapshot.message_id);
  TEST_ASSERT_EQUAL_UINT8(1, snapshot.provider_count);
}

void test_ack_encodes_protocol_version_message_id_and_status() {
  const auto ack =
      agentmeter::make_ack(0x1234, agentmeter::FrameStatus::UnsupportedSchema);

  const uint8_t expected[] = {1, 0x81, 0x34, 0x12, 4};
  TEST_ASSERT_EQUAL_UINT8_ARRAY(expected, ack.data(), ack.size());
}

void test_ui_formats_unknown_usage_and_bounded_reset_countdowns() {
  std::array<char, 16> text{};

  agentmeter::format_usage_percent(-1, text.data(), text.size());
  TEST_ASSERT_EQUAL_STRING("--", text.data());
  agentmeter::format_usage_percent(90, text.data(), text.size());
  TEST_ASSERT_EQUAL_STRING("90%", text.data());
  agentmeter::format_countdown(0, text.data(), text.size());
  TEST_ASSERT_EQUAL_STRING("now", text.data());
  agentmeter::format_countdown(3660, text.data(), text.size());
  TEST_ASSERT_EQUAL_STRING("1h 1m", text.data());
  agentmeter::format_countdown(8 * 86400, text.data(), text.size());
  TEST_ASSERT_EQUAL_STRING("8d", text.data());
}

}  // namespace

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_parse_snapshot_populates_bounded_display_model);
  RUN_TEST(test_countdown_and_staleness_use_rollover_safe_monotonic_time);
  RUN_TEST(
      test_reassembler_applies_snapshot_only_after_final_in_order_fragment);
  RUN_TEST(test_ack_encodes_protocol_version_message_id_and_status);
  RUN_TEST(test_ui_formats_unknown_usage_and_bounded_reset_countdowns);
  return UNITY_END();
}
