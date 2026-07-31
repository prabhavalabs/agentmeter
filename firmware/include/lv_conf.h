#ifndef LV_CONF_H
#define LV_CONF_H

// AgentMeter renders a dark interface on the board's 480x480 AMOLED panel.
#define LV_COLOR_DEPTH 16

// The Arduino application supplies display buffers during hardware bring-up.
#define LV_MEM_SIZE (96U * 1024U)

// Keep the initial font set small. Additional sizes are enabled with the UI.
#define LV_FONT_MONTSERRAT_14 1
#define LV_FONT_MONTSERRAT_18 1
#define LV_FONT_MONTSERRAT_24 1

// Runtime logging is useful during bring-up and can be disabled for releases.
#define LV_USE_LOG 1
#define LV_LOG_LEVEL LV_LOG_LEVEL_WARN

#endif  // LV_CONF_H
