#ifndef LV_CONF_H
#define LV_CONF_H

// AgentMeter renders a dark interface on the board's 480x480 AMOLED panel.
#define LV_COLOR_DEPTH 16

// The Arduino application supplies display buffers during hardware bring-up.
#define LV_MEM_SIZE (96U * 1024U)

// Built-in fonts used by the 480x480 dashboard hierarchy.
#define LV_FONT_MONTSERRAT_12 1
#define LV_FONT_MONTSERRAT_14 1
#define LV_FONT_MONTSERRAT_16 1
#define LV_FONT_MONTSERRAT_18 1
#define LV_FONT_MONTSERRAT_20 1
#define LV_FONT_MONTSERRAT_24 1
#define LV_FONT_MONTSERRAT_28 1
#define LV_FONT_MONTSERRAT_36 1

// Runtime logging is useful during bring-up and can be disabled for releases.
#define LV_USE_LOG 1
#define LV_LOG_LEVEL LV_LOG_LEVEL_WARN

#endif  // LV_CONF_H
