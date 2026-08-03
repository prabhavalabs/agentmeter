#include <Arduino.h>
#include <lvgl.h>

#include <cstdio>

#include "boards/waveshare_amoled_216/board.h"
#include "dashboard_model.h"
#include "device_controller.h"
#include "settings_store.h"
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

class NvsSettingsRepository final : public agentmeter::SettingsRepository {
 public:
  agentmeter::SettingsLoadResult load(
      agentmeter::DeviceSettings& output) override {
    return agentmeter::load_device_settings(output);
  }

  bool save(const agentmeter::DeviceSettings& settings) override {
    return agentmeter::save_device_settings(settings);
  }
};

class BleManagementEventSink final : public agentmeter::ManagementEventSink {
 public:
  bool publish(uint8_t message_type, uint16_t message_id,
               const uint8_t* payload, size_t length) override {
    return agentmeter::transport_publish_management(
        message_type, message_id, payload, length);
  }
};

class BoardDevicePlatform final : public agentmeter::DevicePlatform {
 public:
  agentmeter::DeviceInformation information() override {
    agentmeter::DeviceInformation value{};
    std::snprintf(value.model.data(), value.model.size(), "%s",
                  "waveshare-amoled-216");
    std::snprintf(value.name.data(), value.name.size(), "%s",
                  agentmeter::transport_device_name());
    std::snprintf(value.firmware_version.data(),
                  value.firmware_version.size(), "%s", AGENTMETER_VERSION);
    std::snprintf(value.hardware_revision.data(),
                  value.hardware_revision.size(), "%s", "1");
    value.supports_battery = true;
    value.supports_vbus_voltage = true;
    value.supports_input_current = false;
    return value;
  }

  agentmeter::DeviceTelemetry telemetry(
      const agentmeter::DeviceSettings& settings) override {
    const agentmeter::BoardTelemetry board =
        agentmeter::board_read_telemetry();
    agentmeter::DeviceTelemetry value{};
    value.uptime_seconds = millis() / 1000U;
    value.free_heap_bytes = ESP.getFreeHeap();
    value.minimum_free_heap_bytes = ESP.getMinFreeHeap();
    value.display_on = agentmeter::ui_display_is_on();
    value.display_dimmed = agentmeter::ui_display_is_dimmed();
    value.brightness_percent = settings.brightness_percent;
    value.usb_present = board.usb_present;
    value.battery_present = board.battery_present;
    value.power_source = board.usb_present
                             ? agentmeter::PowerSource::Usb
                             : (board.battery_present
                                    ? agentmeter::PowerSource::Battery
                                    : agentmeter::PowerSource::Unknown);
    value.has_charging = board.charging_available;
    value.charging = board.charging;
    value.has_battery_voltage = board.battery_voltage_available;
    value.battery_voltage_mv = board.battery_voltage_mv;
    value.has_battery_percent = board.battery_percent_available;
    value.battery_percent = board.battery_percent;
    value.has_vbus_voltage = board.vbus_voltage_available;
    value.vbus_voltage_mv = board.vbus_voltage_mv;
    return value;
  }

  void apply_settings(const agentmeter::DeviceSettings& settings) override {
    if (agentmeter::ui_display_is_on()) {
      agentmeter::board_set_brightness_percent(settings.brightness_percent);
    }
  }

  void identify() override { agentmeter::ui_identify(); }
  void restart() override { ESP.restart(); }
  void forget_bonds() override { agentmeter::transport_clear_bonds(); }
};

NvsSettingsRepository settings_repository;
BleManagementEventSink management_event_sink;
BoardDevicePlatform device_platform;
agentmeter::DeviceController device_controller(
    settings_repository, management_event_sink, device_platform);

void snapshot_received(const agentmeter::DashboardSnapshot& snapshot,
                       uint32_t received_at_ms) {
  latest_snapshot = snapshot;
  snapshot_received_at_ms = received_at_ms;
  has_snapshot = true;
  device_controller.set_snapshot(&latest_snapshot);
  agentmeter::ui_set_model(snapshot, received_at_ms);
  agentmeter::ui_set_connection(agentmeter::ConnectionState::Connected);
  Serial.printf("Snapshot: message=%u providers=%u\n", snapshot.message_id,
                snapshot.provider_count);
}

void management_request_received(
    const agentmeter::ManagementRequest& request, uint32_t received_at_ms) {
  device_controller.handle(request, received_at_ms);
  agentmeter::ui_apply_settings(device_controller.settings());
}

void settings_changed_from_ui(const agentmeter::DeviceSettings& settings,
                              uint32_t changed_at_ms) {
  device_controller.settings_changed_from_ui(settings, changed_at_ms);
  agentmeter::ui_apply_settings(device_controller.settings());
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
  const agentmeter::SettingsLoadResult settings_result =
      device_controller.begin();
  if (settings_result == agentmeter::SettingsLoadResult::StorageError) {
    Serial.println("Settings: storage unavailable; safe defaults active");
  }
  if (!agentmeter::transport_begin(snapshot_received,
                                   management_request_received)) {
    Serial.println("Transport: Bluetooth unavailable; USB serial remains active");
  }

  agentmeter::ui_begin(agentmeter::transport_device_name(),
                       device_controller.settings(), settings_changed_from_ui);
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
  device_controller.tick(now_ms);
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
