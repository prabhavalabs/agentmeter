#include "ui_layout.h"

#include <algorithm>

namespace agentmeter {

CardFrame overview_card_frame(uint8_t visible_count, uint8_t visible_index) {
  if (visible_count <= 1) {
    return CardFrame{20, 20, 440, 340};
  }
  if (visible_count == 2) {
    return CardFrame{20, static_cast<int16_t>(10 + visible_index * 186), 440,
                     176};
  }
  return CardFrame{
      static_cast<int16_t>(visible_index % 2 == 0 ? 14 : 247),
      static_cast<int16_t>(8 + (visible_index / 2) * 190), 219, 180};
}

int16_t overview_content_height(uint8_t visible_count) {
  if (visible_count <= 4) {
    return 398;
  }
  const int16_t rows = static_cast<int16_t>((visible_count + 1) / 2);
  return std::max<int16_t>(398, static_cast<int16_t>(rows * 190 + 8));
}

}  // namespace agentmeter
