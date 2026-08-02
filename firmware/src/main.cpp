#include <Arduino.h>
#include <lvgl.h>

#include "boards/waveshare_amoled_216/board.h"
#include "dashboard_model.h"
#include "transport.h"
#include "ui.h"

namespace {

constexpr uint32_t kButtonDebounceMs = 40;
constexpr uint32_t kClearPairingHoldMs = 5000;
constexpr uint32_t kHeartbeatIntervalMs = 30000;

agentmeter::DashboardSnapshot latest_snapshot{};
bool app_ready = false;
bool has_snapshot = false;
bool raw_button_pressed = false;
bool stable_button_pressed = false;
bool long_press_handled = false;
uint32_t snapshot_received_at_ms = 0;
uint32_t raw_button_changed_at_ms = 0;
uint32_t button_pressed_at_ms = 0;
uint32_t last_heartbeat_ms = 0;

void snapshot_received(const agentmeter::DashboardSnapshot& snapshot,
                       uint32_t received_at_ms) {
  latest_snapshot = snapshot;
  snapshot_received_at_ms = received_at_ms;
  has_snapshot = true;
  agentmeter::ui_set_model(snapshot, received_at_ms);
  agentmeter::ui_set_connection(agentmeter::ConnectionState::Connected);
  Serial.printf("Snapshot: message=%u providers=%u\n", snapshot.message_id,
                snapshot.provider_count);
}

void update_button(uint32_t now_ms) {
  const bool pressed = agentmeter::board_button_pressed();
  if (pressed != raw_button_pressed) {
    raw_button_pressed = pressed;
    raw_button_changed_at_ms = now_ms;
  }

  if (pressed != stable_button_pressed &&
      now_ms - raw_button_changed_at_ms >= kButtonDebounceMs) {
    stable_button_pressed = pressed;
    if (pressed) {
      button_pressed_at_ms = now_ms;
      long_press_handled = false;
    } else if (!long_press_handled) {
      agentmeter::ui_toggle_view();
    }
  }

  if (stable_button_pressed && !long_press_handled &&
      now_ms - button_pressed_at_ms >= kClearPairingHoldMs) {
    long_press_handled = true;
    agentmeter::transport_clear_bonds();
    agentmeter::ui_show_pairing_cleared();
  }
}

void update_connection_state(uint32_t now_ms) {
  if (!has_snapshot) {
    agentmeter::ui_set_connection(agentmeter::ConnectionState::Waiting);
    return;
  }
  if (agentmeter::is_stale(latest_snapshot, snapshot_received_at_ms, now_ms)) {
    agentmeter::ui_set_connection(agentmeter::ConnectionState::Stale);
  } else if (agentmeter::transport_is_connected()) {
    agentmeter::ui_set_connection(agentmeter::ConnectionState::Connected);
  } else {
    agentmeter::ui_set_connection(agentmeter::ConnectionState::Reconnecting);
  }
}

}  // namespace

void setup() {
  Serial.begin(115200);
  delay(300);

  Serial.println();
  Serial.print("AgentMeter firmware ");
  Serial.println(AGENTMETER_VERSION);
  Serial.println("Board: Waveshare ESP32-S3-Touch-AMOLED-2.16");

  if (!agentmeter::board_init()) {
    Serial.println("Board: initialization failed; app stopped");
    return;
  }
  if (!agentmeter::transport_begin(snapshot_received)) {
    Serial.println("Transport: Bluetooth unavailable; USB serial remains active");
  }

  agentmeter::ui_begin(agentmeter::transport_device_name());
  lv_timer_handler();
  app_ready = true;
  Serial.println("AgentMeter: ready");
}

void loop() {
  if (!app_ready) {
    delay(1000);
    return;
  }

  const uint32_t now_ms = millis();
  agentmeter::transport_loop();
  update_button(now_ms);
  update_connection_state(now_ms);
  agentmeter::ui_tick(now_ms);
  lv_timer_handler();

  if (now_ms - last_heartbeat_ms >= kHeartbeatIntervalMs) {
    last_heartbeat_ms = now_ms;
    Serial.printf("Heartbeat: uptime=%lu s, heap=%u, minimum=%u\n",
                  static_cast<unsigned long>(now_ms / 1000), ESP.getFreeHeap(),
                  ESP.getMinFreeHeap());
  }
  delay(5);
}
