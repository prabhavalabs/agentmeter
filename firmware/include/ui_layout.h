#pragma once

#include <cstdint>

namespace agentmeter {

struct CardFrame {
  int16_t x;
  int16_t y;
  int16_t width;
  int16_t height;
};

CardFrame overview_card_frame(uint8_t visible_count, uint8_t visible_index);
int16_t overview_content_height(uint8_t visible_count);

}  // namespace agentmeter
