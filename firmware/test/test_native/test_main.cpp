#include <cstring>
#include <string>
#include <vector>

#include <unity.h>

#include "dashboard_model.h"
#include "provider_visuals.h"
#include "protocol.h"
#include "settings_model.h"
#include "ui_layout.h"
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

void test_cursor_visuals_use_warm_neutral_cube_mark() {
  const agentmeter::ProviderVisuals visuals =
      agentmeter::provider_visuals("cursor");

  TEST_ASSERT_EQUAL_HEX32(0xD6D5CC, visuals.accent_rgb);
  TEST_ASSERT_EQUAL(static_cast<int>(agentmeter::ProviderMark::CursorCube),
                    static_cast<int>(visuals.mark));
}

void test_dashboard_preferences_filter_providers_by_stable_id() {
  agentmeter::DashboardSnapshot snapshot{};
  snapshot.provider_count = 3;
  std::strcpy(snapshot.providers[0].id.data(), "codex");
  std::strcpy(snapshot.providers[1].id.data(), "claude");
  std::strcpy(snapshot.providers[2].id.data(), "gemini");
  agentmeter::DashboardPreferences preferences{};

  TEST_ASSERT_TRUE(
      agentmeter::set_provider_visible(preferences, "gemini", false));
  std::array<uint8_t, agentmeter::kMaximumProviders> visible{};
  const uint8_t count = agentmeter::visible_provider_indices(
      snapshot, preferences, visible);

  TEST_ASSERT_EQUAL_UINT8(2, count);
  TEST_ASSERT_EQUAL_UINT8(0, visible[0]);
  TEST_ASSERT_EQUAL_UINT8(1, visible[1]);
  TEST_ASSERT_FALSE(
      agentmeter::is_provider_visible(preferences, "gemini"));
  TEST_ASSERT_TRUE(agentmeter::is_provider_visible(preferences, "codex"));
}

void test_dashboard_preferences_round_trip_hidden_provider_ids() {
  agentmeter::DashboardPreferences original{};
  TEST_ASSERT_TRUE(
      agentmeter::set_provider_visible(original, "gemini", false));
  TEST_ASSERT_TRUE(
      agentmeter::set_provider_visible(original, "future-agent", false));
  std::array<char, 256> encoded{};

  TEST_ASSERT_TRUE(agentmeter::encode_hidden_provider_ids(
      original, encoded.data(), encoded.size()));
  TEST_ASSERT_EQUAL_STRING("gemini,future-agent", encoded.data());

  agentmeter::DashboardPreferences restored{};
  TEST_ASSERT_TRUE(
      agentmeter::decode_hidden_provider_ids(encoded.data(), restored));
  TEST_ASSERT_FALSE(
      agentmeter::is_provider_visible(restored, "gemini"));
  TEST_ASSERT_FALSE(
      agentmeter::is_provider_visible(restored, "future-agent"));
  TEST_ASSERT_TRUE(agentmeter::is_provider_visible(restored, "claude"));
}

void test_full_view_rotation_skips_hidden_providers_and_wraps() {
  agentmeter::DashboardSnapshot snapshot{};
  snapshot.provider_count = 3;
  std::strcpy(snapshot.providers[0].id.data(), "codex");
  std::strcpy(snapshot.providers[1].id.data(), "claude");
  std::strcpy(snapshot.providers[2].id.data(), "gemini");
  agentmeter::DashboardPreferences preferences{};
  agentmeter::set_provider_visible(preferences, "claude", false);

  TEST_ASSERT_EQUAL_UINT8(
      2, agentmeter::next_visible_provider(snapshot, preferences, 0));
  TEST_ASSERT_EQUAL_UINT8(
      0, agentmeter::next_visible_provider(snapshot, preferences, 2));
}

void test_rotation_interval_accepts_three_to_sixty_seconds() {
  agentmeter::DashboardPreferences preferences{};

  TEST_ASSERT_EQUAL_UINT8(3, preferences.rotation_seconds);
  TEST_ASSERT_FALSE(agentmeter::set_rotation_seconds(preferences, 2));
  TEST_ASSERT_EQUAL_UINT8(3, preferences.rotation_seconds);
  TEST_ASSERT_TRUE(agentmeter::set_rotation_seconds(preferences, 15));
  TEST_ASSERT_EQUAL_UINT8(15, preferences.rotation_seconds);
  TEST_ASSERT_FALSE(agentmeter::set_rotation_seconds(preferences, 61));
  TEST_ASSERT_EQUAL_UINT8(15, preferences.rotation_seconds);
}

void test_overview_layout_uses_two_columns_and_scrolls_after_four_cards() {
  const agentmeter::CardFrame first = agentmeter::overview_card_frame(5, 0);
  const agentmeter::CardFrame second = agentmeter::overview_card_frame(5, 1);
  const agentmeter::CardFrame fifth = agentmeter::overview_card_frame(5, 4);

  TEST_ASSERT_EQUAL_INT16(14, first.x);
  TEST_ASSERT_EQUAL_INT16(247, second.x);
  TEST_ASSERT_EQUAL_INT16(first.y + 190 * 2, fifth.y);
  TEST_ASSERT_EQUAL_INT16(219, fifth.width);
  TEST_ASSERT_GREATER_THAN_INT16(398, agentmeter::overview_content_height(5));
}

void test_two_provider_layout_uses_full_width_rows() {
  const agentmeter::CardFrame first = agentmeter::overview_card_frame(2, 0);
  const agentmeter::CardFrame second = agentmeter::overview_card_frame(2, 1);

  TEST_ASSERT_EQUAL_INT16(20, first.x);
  TEST_ASSERT_EQUAL_INT16(440, first.width);
  TEST_ASSERT_EQUAL_INT16(10, first.y);
  TEST_ASSERT_EQUAL_INT16(196, second.y);
  TEST_ASSERT_EQUAL_INT16(398, agentmeter::overview_content_height(2));
}

void test_snapshot_parser_accepts_five_providers_for_scrollable_dashboard() {
  const std::string payload = R"json({
    "schemaVersion": 1,
    "messageId": 43,
    "generatedAtEpoch": 1785508800,
    "staleAfterSeconds": 180,
    "providers": [
      {"id":"one","name":"One","status":"ok","windows":[]},
      {"id":"two","name":"Two","status":"ok","windows":[]},
      {"id":"three","name":"Three","status":"ok","windows":[]},
      {"id":"four","name":"Four","status":"ok","windows":[]},
      {"id":"five","name":"Five","status":"ok","windows":[]}
    ],
    "display": {
      "brightnessPercent": 55,
      "dimAfterSeconds": 300,
      "screenOffAfterSeconds": 1800,
      "alertThresholds": [75, 90],
      "soundEnabled": false
    },
    "event": null
  })json";
  agentmeter::DashboardSnapshot snapshot{};

  const auto status = agentmeter::parse_snapshot(
      reinterpret_cast<const uint8_t*>(payload.data()), payload.size(),
      snapshot);

  TEST_ASSERT_EQUAL(static_cast<int>(agentmeter::ParseStatus::Ok),
                    static_cast<int>(status));
  TEST_ASSERT_EQUAL_UINT8(5, snapshot.provider_count);
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
  RUN_TEST(test_cursor_visuals_use_warm_neutral_cube_mark);
  RUN_TEST(test_dashboard_preferences_filter_providers_by_stable_id);
  RUN_TEST(test_dashboard_preferences_round_trip_hidden_provider_ids);
  RUN_TEST(test_full_view_rotation_skips_hidden_providers_and_wraps);
  RUN_TEST(test_rotation_interval_accepts_three_to_sixty_seconds);
  RUN_TEST(
      test_overview_layout_uses_two_columns_and_scrolls_after_four_cards);
  RUN_TEST(test_two_provider_layout_uses_full_width_rows);
  RUN_TEST(
      test_snapshot_parser_accepts_five_providers_for_scrollable_dashboard);
  return UNITY_END();
}
