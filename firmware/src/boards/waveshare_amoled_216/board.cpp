#include "board.h"

#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include <Wire.h>
#include <esp_heap_caps.h>

#define XPOWERS_CHIP_AXP2101
#include <TouchDrvCSTXXX.hpp>
#include <XPowersLib.h>

namespace agentmeter {
namespace {

// Waveshare ESP32-S3-Touch-AMOLED-2.16 pin map.
constexpr int8_t kLcdData0 = 4;
constexpr int8_t kLcdData1 = 5;
constexpr int8_t kLcdData2 = 6;
constexpr int8_t kLcdData3 = 7;
constexpr int8_t kLcdChipSelect = 12;
constexpr int8_t kLcdClock = 38;
constexpr int8_t kLcdReset = 39;

constexpr int8_t kI2cClock = 14;
constexpr int8_t kI2cData = 15;
constexpr int8_t kTouchInterrupt = 11;
constexpr int8_t kTouchReset = 40;
constexpr int8_t kUserButton = 18;

constexpr uint8_t kInitialBrightnessPercent = 55;
constexpr uint16_t kDrawBufferLines = 40;
constexpr size_t kDrawBufferBytes =
    static_cast<size_t>(kDisplayWidth) * kDrawBufferLines * sizeof(uint16_t);

Arduino_ESP32QSPI display_bus(kLcdChipSelect, kLcdClock, kLcdData0,
                              kLcdData1, kLcdData2, kLcdData3);
Arduino_CO5300 display_panel(&display_bus, kLcdReset, 0, kDisplayWidth,
                             kDisplayHeight, 0, 0, 0, 0);
XPowersPMU power_manager;
TouchDrvCST92xx touch_controller;

lv_display_t* lv_display = nullptr;
lv_indev_t* lv_touch = nullptr;
uint8_t* draw_buffer_1 = nullptr;
uint8_t* draw_buffer_2 = nullptr;

bool display_ready = false;
bool touch_ready = false;
bool pmu_ready = false;
volatile bool touch_pending = false;
uint32_t flush_count = 0;
uint64_t flush_time_us = 0;

void IRAM_ATTR touch_interrupt_handler() { touch_pending = true; }

bool take_touch_pending() {
  noInterrupts();
  const bool pending = touch_pending;
  touch_pending = false;
  interrupts();
  return pending;
}

void round_invalidated_area(lv_event_t* event) {
  lv_area_t* area = lv_event_get_invalidated_area(event);
  if (area == nullptr) {
    return;
  }

  area->x1 &= ~1;
  area->y1 &= ~1;
  if ((area->x2 & 1) == 0 && area->x2 < kDisplayWidth - 1) {
    area->x2++;
  }
  if ((area->y2 & 1) == 0 && area->y2 < kDisplayHeight - 1) {
    area->y2++;
  }
}

void touch_read_callback(lv_indev_t*, lv_indev_data_t* data) {
  int16_t x = 0;
  int16_t y = 0;
  if (board_read_touch(x, y)) {
    data->state = LV_INDEV_STATE_PRESSED;
    data->point.x = x;
    data->point.y = y;
    return;
  }

  data->state = LV_INDEV_STATE_RELEASED;
}

uint32_t lvgl_tick_ms() { return millis(); }

#if LV_USE_LOG != 0
void lvgl_log(lv_log_level_t, const char* message) {
  Serial.print("LVGL: ");
  Serial.println(message);
}
#endif

void log_memory() {
  Serial.printf("Memory: heap=%u bytes, minimum=%u bytes\n", ESP.getFreeHeap(),
                ESP.getMinFreeHeap());
  Serial.printf("Memory: PSRAM=%u bytes, free=%u bytes\n",
                ESP.getPsramSize(), ESP.getFreePsram());
  Serial.printf("LVGL: two %u-byte partial buffers in PSRAM\n",
                static_cast<unsigned>(kDrawBufferBytes));
}

}  // namespace

bool board_init() {
  const uint32_t started_at_ms = millis();

  pinMode(kUserButton, INPUT_PULLUP);
  Wire.begin(kI2cData, kI2cClock);
  Wire.setClock(400000);

  pmu_ready = power_manager.begin(
      Wire, AXP2101_SLAVE_ADDRESS, kI2cData, kI2cClock);
  if (pmu_ready) {
    power_manager.enableBattDetection();
    power_manager.enableBattVoltageMeasure();
    power_manager.enableVbusVoltageMeasure();
    Serial.printf("PMU: AXP2101 online, USB=%s, battery=%s\n",
                  power_manager.isVbusGood() ? "yes" : "no",
                  power_manager.isBatteryConnect() ? "yes" : "no");
  } else {
    Serial.println("PMU: AXP2101 not detected; continuing on USB power");
  }

  touch_controller.setPins(kTouchReset, kTouchInterrupt);
  touch_ready = touch_controller.begin(Wire, CST92XX_SLAVE_ADDRESS,
                                       kI2cData, kI2cClock);
  Wire.setClock(400000);
  if (touch_ready) {
    touch_controller.setMaxCoordinates(kDisplayWidth, kDisplayHeight);
    touch_controller.setSwapXY(true);
    touch_controller.setMirrorXY(true, false);
    pinMode(kTouchInterrupt, INPUT_PULLUP);
    attachInterrupt(digitalPinToInterrupt(kTouchInterrupt),
                    touch_interrupt_handler, FALLING);
    touch_pending = true;
    Serial.printf("Touch: %s online at 0x%02X\n",
                  touch_controller.getModelName(), CST92XX_SLAVE_ADDRESS);
  } else {
    Serial.println("Touch: CST9220 not detected; display test will continue");
  }

  if (!display_panel.begin()) {
    Serial.println("Display: CO5300 initialization failed");
    return false;
  }
  display_ready = true;
  display_bus.writeC8D8(0x36, 0xA0);
  display_panel.fillScreen(RGB565_BLACK);
  board_set_brightness_percent(kInitialBrightnessPercent);
  Serial.println("Display: CO5300 online at 480x480");

  if (!psramFound()) {
    Serial.println("Memory: OPI PSRAM was not detected");
    display_panel.fillScreen(RGB565_RED);
    return false;
  }

  draw_buffer_1 = static_cast<uint8_t*>(
      heap_caps_malloc(kDrawBufferBytes, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT));
  draw_buffer_2 = static_cast<uint8_t*>(
      heap_caps_malloc(kDrawBufferBytes, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT));
  if (draw_buffer_1 == nullptr || draw_buffer_2 == nullptr) {
    Serial.println("Memory: unable to allocate LVGL buffers in PSRAM");
    display_panel.fillScreen(RGB565_RED);
    return false;
  }

  lv_init();
  lv_tick_set_cb(lvgl_tick_ms);
#if LV_USE_LOG != 0
  lv_log_register_print_cb(lvgl_log);
#endif

  lv_display = lv_display_create(kDisplayWidth, kDisplayHeight);
  lv_display_set_color_format(lv_display, LV_COLOR_FORMAT_RGB565);
  lv_display_set_flush_cb(lv_display, board_display_flush);
  lv_display_set_buffers(lv_display, draw_buffer_1, draw_buffer_2,
                         kDrawBufferBytes, LV_DISPLAY_RENDER_MODE_PARTIAL);
  lv_display_add_event_cb(lv_display, round_invalidated_area,
                          LV_EVENT_INVALIDATE_AREA, nullptr);

  if (touch_ready) {
    lv_touch = lv_indev_create();
    lv_indev_set_type(lv_touch, LV_INDEV_TYPE_POINTER);
    lv_indev_set_read_cb(lv_touch, touch_read_callback);
    lv_indev_set_display(lv_touch, lv_display);
  }

  log_memory();
  Serial.printf("Board: initialization completed in %u ms\n",
                millis() - started_at_ms);
  return true;
}

void board_display_flush(lv_display_t* lvgl_display, const lv_area_t* area,
                         uint8_t* pixels) {
  if (!display_ready || area == nullptr || pixels == nullptr) {
    lv_display_flush_ready(lvgl_display);
    return;
  }

  const uint32_t started_at_us = micros();
  const int16_t width = static_cast<int16_t>(lv_area_get_width(area));
  const int16_t height = static_cast<int16_t>(lv_area_get_height(area));
  display_panel.draw16bitRGBBitmap(
      static_cast<int16_t>(area->x1), static_cast<int16_t>(area->y1),
      reinterpret_cast<uint16_t*>(pixels), width, height);
  flush_time_us += micros() - started_at_us;
  flush_count++;

  if (flush_count % 600 == 0) {
    Serial.printf("Display: %u flushes, average %llu us\n", flush_count,
                  flush_time_us / flush_count);
  }
  lv_display_flush_ready(lvgl_display);
}

bool board_read_touch(int16_t& x, int16_t& y) {
  if (!touch_ready) {
    return false;
  }

  if (!take_touch_pending() && digitalRead(kTouchInterrupt) != LOW) {
    return false;
  }

  int16_t x_points[5] = {};
  int16_t y_points[5] = {};
  const uint8_t point_count = touch_controller.getPoint(
      x_points, y_points, touch_controller.getSupportTouchPoint());
  if (point_count == 0) {
    return false;
  }

  x = x_points[0];
  y = y_points[0];
  return true;
}

void board_set_brightness(uint8_t brightness) {
  if (display_ready) {
    display_panel.setBrightness(brightness);
  }
}

void board_set_brightness_percent(uint8_t brightness_percent) {
  const uint8_t clamped =
      static_cast<uint8_t>(constrain(brightness_percent, 1, 100));
  board_set_brightness(
      static_cast<uint8_t>((static_cast<uint16_t>(clamped) * 255U) / 100U));
}

BoardTelemetry board_read_telemetry() {
  BoardTelemetry telemetry{};
  telemetry.pmu_available = pmu_ready;
  if (!pmu_ready) {
    return telemetry;
  }

  telemetry.usb_present = power_manager.isVbusGood();
  telemetry.battery_present = power_manager.isBatteryConnect();
  telemetry.vbus_voltage_available = true;
  telemetry.vbus_voltage_mv = power_manager.getVbusVoltage();
  if (telemetry.battery_present) {
    telemetry.charging_available = true;
    telemetry.charging = power_manager.isCharging();
    telemetry.battery_voltage_available = true;
    telemetry.battery_voltage_mv = power_manager.getBattVoltage();
    const int battery_percent = power_manager.getBatteryPercent();
    if (battery_percent >= 0 && battery_percent <= 100) {
      telemetry.battery_percent_available = true;
      telemetry.battery_percent = static_cast<uint8_t>(battery_percent);
    }
  }
  return telemetry;
}

bool board_button_pressed() { return digitalRead(kUserButton) == LOW; }

bool board_play_tone(uint16_t, uint16_t) {
  // The speaker is behind the ES8311 I2S codec. Audio initialization belongs
  // in its own driver milestone; a GPIO tone would not reach the speaker.
  return false;
}

}  // namespace agentmeter
