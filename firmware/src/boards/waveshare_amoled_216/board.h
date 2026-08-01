#pragma once

#include <cstdint>

#include <lvgl.h>

namespace agentmeter {

inline constexpr int16_t kDisplayWidth = 480;
inline constexpr int16_t kDisplayHeight = 480;

bool board_init();
void board_display_flush(lv_display_t* display, const lv_area_t* area,
                         uint8_t* pixels);
bool board_read_touch(int16_t& x, int16_t& y);
void board_set_brightness(uint8_t brightness);
bool board_button_pressed();
bool board_play_tone(uint16_t frequency_hz, uint16_t duration_ms);

}  // namespace agentmeter
