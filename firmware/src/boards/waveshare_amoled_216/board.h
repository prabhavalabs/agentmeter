#pragma once

#include <cstdint>

#include <lvgl.h>

namespace agentmeter {

inline constexpr int16_t kDisplayWidth = 480;
inline constexpr int16_t kDisplayHeight = 480;

struct BoardTelemetry {
  bool pmu_available = false;
  bool usb_present = false;
  bool battery_present = false;
  bool charging_available = false;
  bool charging = false;
  bool battery_voltage_available = false;
  uint16_t battery_voltage_mv = 0;
  bool battery_percent_available = false;
  uint8_t battery_percent = 0;
  bool vbus_voltage_available = false;
  uint16_t vbus_voltage_mv = 0;
};

bool board_init();
void board_display_flush(lv_display_t* display, const lv_area_t* area,
                         uint8_t* pixels);
bool board_read_touch(int16_t& x, int16_t& y);
void board_set_brightness(uint8_t brightness);
void board_set_brightness_percent(uint8_t brightness_percent);
BoardTelemetry board_read_telemetry();
bool board_button_pressed();
bool board_play_tone(uint16_t frequency_hz, uint16_t duration_ms);

}  // namespace agentmeter
