#include <Arduino.h>
#include <lvgl.h>

#include "boards/waveshare_amoled_216/board.h"

namespace {

constexpr uint8_t kBrightnessLevels[] = {75, 150, 230};
constexpr uint32_t kHeartbeatIntervalMs = 5000;
constexpr uint32_t kButtonDebounceMs = 40;

lv_obj_t* touch_marker = nullptr;
lv_obj_t* touch_label = nullptr;
lv_obj_t* button_label = nullptr;
uint8_t brightness_index = 1;
bool previous_button_state = false;
bool diagnostic_ready = false;
uint32_t button_changed_at_ms = 0;
uint32_t last_heartbeat_ms = 0;

void style_card(lv_obj_t* card) {
  lv_obj_set_style_bg_color(card, lv_color_hex(0x151C2E), 0);
  lv_obj_set_style_bg_opa(card, LV_OPA_90, 0);
  lv_obj_set_style_border_color(card, lv_color_hex(0x263653), 0);
  lv_obj_set_style_border_width(card, 1, 0);
  lv_obj_set_style_radius(card, 16, 0);
  lv_obj_set_style_pad_all(card, 14, 0);
  lv_obj_remove_flag(card, LV_OBJ_FLAG_SCROLLABLE);
}

lv_obj_t* create_status_card(lv_obj_t* parent, int16_t y, const char* title,
                             const char* value, lv_color_t accent) {
  lv_obj_t* card = lv_obj_create(parent);
  lv_obj_set_pos(card, 220, y);
  lv_obj_set_size(card, 232, 64);
  style_card(card);

  lv_obj_t* dot = lv_obj_create(card);
  lv_obj_set_pos(dot, 0, 5);
  lv_obj_set_size(dot, 10, 10);
  lv_obj_set_style_radius(dot, LV_RADIUS_CIRCLE, 0);
  lv_obj_set_style_bg_color(dot, accent, 0);
  lv_obj_set_style_border_width(dot, 0, 0);

  lv_obj_t* title_label = lv_label_create(card);
  lv_label_set_text(title_label, title);
  lv_obj_set_pos(title_label, 20, -1);
  lv_obj_set_style_text_color(title_label, lv_color_hex(0x8491A8), 0);
  lv_obj_set_style_text_font(title_label, &lv_font_montserrat_14, 0);

  lv_obj_t* value_label = lv_label_create(card);
  lv_label_set_text(value_label, value);
  lv_obj_set_pos(value_label, 20, 22);
  lv_obj_set_style_text_color(value_label, lv_color_hex(0xF1F5FF), 0);
  lv_obj_set_style_text_font(value_label, &lv_font_montserrat_14, 0);
  return value_label;
}

void touch_event(lv_event_t* event) {
  const lv_event_code_t code = lv_event_get_code(event);
  if (code != LV_EVENT_PRESSED && code != LV_EVENT_PRESSING) {
    return;
  }

  lv_indev_t* input = lv_indev_active();
  if (input == nullptr) {
    return;
  }

  lv_point_t point;
  lv_indev_get_point(input, &point);
  lv_obj_set_pos(touch_marker, point.x - 9, point.y - 9);
  lv_obj_remove_flag(touch_marker, LV_OBJ_FLAG_HIDDEN);
  lv_label_set_text_fmt(touch_label, "TOUCH OK  x:%ld  y:%ld",
                        static_cast<long>(point.x),
                        static_cast<long>(point.y));
  Serial.printf("Touch: x=%ld y=%ld\n", static_cast<long>(point.x),
                static_cast<long>(point.y));
}

void animate_square(void* object, int32_t x) {
  lv_obj_set_x(static_cast<lv_obj_t*>(object), x);
}

void create_diagnostic_screen() {
  lv_obj_t* screen = lv_screen_active();
  lv_obj_set_style_bg_color(screen, lv_color_hex(0x070A12), 0);
  lv_obj_set_style_bg_grad_color(screen, lv_color_hex(0x101A32), 0);
  lv_obj_set_style_bg_grad_dir(screen, LV_GRAD_DIR_VER, 0);
  lv_obj_set_style_text_color(screen, lv_color_hex(0xF1F5FF), 0);
  lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE);

  lv_obj_t* title = lv_label_create(screen);
  lv_label_set_text(title, "AgentMeter");
  lv_obj_set_pos(title, 28, 22);
  lv_obj_set_style_text_font(title, &lv_font_montserrat_24, 0);

  lv_obj_t* subtitle = lv_label_create(screen);
  lv_label_set_text(subtitle, "HARDWARE BRING-UP  /  0.1.0");
  lv_obj_set_pos(subtitle, 29, 54);
  lv_obj_set_style_text_color(subtitle, lv_color_hex(0x7F8DA6), 0);
  lv_obj_set_style_text_font(subtitle, &lv_font_montserrat_14, 0);

  lv_obj_t* badge = lv_obj_create(screen);
  lv_obj_set_pos(badge, 361, 22);
  lv_obj_set_size(badge, 90, 32);
  lv_obj_set_style_radius(badge, 16, 0);
  lv_obj_set_style_bg_color(badge, lv_color_hex(0x123D35), 0);
  lv_obj_set_style_border_width(badge, 0, 0);
  lv_obj_set_style_pad_all(badge, 0, 0);
  lv_obj_remove_flag(badge, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_t* badge_label = lv_label_create(badge);
  lv_label_set_text(badge_label, "ONLINE");
  lv_obj_center(badge_label);
  lv_obj_set_style_text_color(badge_label, lv_color_hex(0x55E6B5), 0);
  lv_obj_set_style_text_font(badge_label, &lv_font_montserrat_14, 0);

  lv_obj_t* arc = lv_arc_create(screen);
  lv_obj_set_pos(arc, 35, 128);
  lv_obj_set_size(arc, 160, 160);
  lv_arc_set_rotation(arc, 135);
  lv_arc_set_bg_angles(arc, 0, 270);
  lv_arc_set_range(arc, 0, 100);
  lv_arc_set_value(arc, 68);
  lv_obj_remove_style(arc, nullptr, LV_PART_KNOB);
  lv_obj_remove_flag(arc, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_set_style_arc_width(arc, 14, LV_PART_MAIN);
  lv_obj_set_style_arc_color(arc, lv_color_hex(0x263653), LV_PART_MAIN);
  lv_obj_set_style_arc_width(arc, 14, LV_PART_INDICATOR);
  lv_obj_set_style_arc_color(arc, lv_color_hex(0x7C5CFC),
                             LV_PART_INDICATOR);

  lv_obj_t* arc_value = lv_label_create(screen);
  lv_label_set_text(arc_value, "68%");
  lv_obj_set_pos(arc_value, 82, 174);
  lv_obj_set_style_text_font(arc_value, &lv_font_montserrat_24, 0);

  lv_obj_t* arc_caption = lv_label_create(screen);
  lv_label_set_text(arc_caption, "DISPLAY TEST");
  lv_obj_set_pos(arc_caption, 61, 211);
  lv_obj_set_style_text_color(arc_caption, lv_color_hex(0x8491A8), 0);
  lv_obj_set_style_text_font(arc_caption, &lv_font_montserrat_14, 0);

  create_status_card(screen, 106, "AMOLED", "480 x 480  /  CO5300",
                     lv_color_hex(0x55E6B5));
  create_status_card(screen, 178, "TOUCH", "Tap anywhere to test",
                     lv_color_hex(0x38BDF8));
  button_label = create_status_card(screen, 250, "BUTTON",
                                    "Press top GPIO18 key",
                                    lv_color_hex(0xF6C85F));

  lv_obj_t* memory_label = lv_label_create(screen);
  lv_label_set_text(memory_label, "DOUBLE-BUFFERED IN OPI PSRAM");
  lv_obj_set_pos(memory_label, 31, 329);
  lv_obj_set_style_text_color(memory_label, lv_color_hex(0x8491A8), 0);
  lv_obj_set_style_text_font(memory_label, &lv_font_montserrat_14, 0);

  lv_obj_t* track = lv_obj_create(screen);
  lv_obj_set_pos(track, 28, 411);
  lv_obj_set_size(track, 424, 38);
  lv_obj_set_style_bg_color(track, lv_color_hex(0x11182A), 0);
  lv_obj_set_style_border_width(track, 0, 0);
  lv_obj_set_style_radius(track, 19, 0);
  lv_obj_set_style_pad_all(track, 0, 0);
  lv_obj_remove_flag(track, LV_OBJ_FLAG_SCROLLABLE);

  lv_obj_t* moving_square = lv_obj_create(screen);
  lv_obj_set_pos(moving_square, 31, 414);
  lv_obj_set_size(moving_square, 32, 32);
  lv_obj_set_style_bg_color(moving_square, lv_color_hex(0x7C5CFC), 0);
  lv_obj_set_style_bg_grad_color(moving_square, lv_color_hex(0x38BDF8), 0);
  lv_obj_set_style_bg_grad_dir(moving_square, LV_GRAD_DIR_HOR, 0);
  lv_obj_set_style_border_width(moving_square, 0, 0);
  lv_obj_set_style_radius(moving_square, 9, 0);

  lv_anim_t animation;
  lv_anim_init(&animation);
  lv_anim_set_var(&animation, moving_square);
  lv_anim_set_exec_cb(&animation, animate_square);
  lv_anim_set_values(&animation, 31, 417);
  lv_anim_set_duration(&animation, 2200);
  lv_anim_set_reverse_duration(&animation, 2200);
  lv_anim_set_repeat_count(&animation, LV_ANIM_REPEAT_INFINITE);
  lv_anim_set_path_cb(&animation, lv_anim_path_ease_in_out);
  lv_anim_start(&animation);

  lv_obj_t* touch_layer = lv_obj_create(screen);
  lv_obj_set_pos(touch_layer, 0, 0);
  lv_obj_set_size(touch_layer, agentmeter::kDisplayWidth,
                  agentmeter::kDisplayHeight);
  lv_obj_set_style_bg_opa(touch_layer, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width(touch_layer, 0, 0);
  lv_obj_set_style_pad_all(touch_layer, 0, 0);
  lv_obj_remove_flag(touch_layer, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_add_flag(touch_layer, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_add_event_cb(touch_layer, touch_event, LV_EVENT_PRESSED, nullptr);
  lv_obj_add_event_cb(touch_layer, touch_event, LV_EVENT_PRESSING, nullptr);

  touch_marker = lv_obj_create(touch_layer);
  lv_obj_set_size(touch_marker, 18, 18);
  lv_obj_set_style_radius(touch_marker, LV_RADIUS_CIRCLE, 0);
  lv_obj_set_style_bg_color(touch_marker, lv_color_hex(0x38BDF8), 0);
  lv_obj_set_style_border_color(touch_marker, lv_color_hex(0xF1F5FF), 0);
  lv_obj_set_style_border_width(touch_marker, 2, 0);
  lv_obj_add_flag(touch_marker, LV_OBJ_FLAG_HIDDEN);

  touch_label = lv_label_create(touch_layer);
  lv_label_set_text(touch_label, "TOUCH WAITING");
  lv_obj_set_pos(touch_label, 31, 367);
  lv_obj_set_style_text_color(touch_label, lv_color_hex(0x38BDF8), 0);
  lv_obj_set_style_text_font(touch_label, &lv_font_montserrat_14, 0);

  Serial.println("UI: diagnostic screen created");
}

void update_button() {
  const uint32_t now = millis();
  const bool pressed = agentmeter::board_button_pressed();
  if (pressed != previous_button_state &&
      now - button_changed_at_ms >= kButtonDebounceMs) {
    previous_button_state = pressed;
    button_changed_at_ms = now;
    if (pressed) {
      brightness_index =
          (brightness_index + 1) % (sizeof(kBrightnessLevels) /
                                    sizeof(kBrightnessLevels[0]));
      const uint8_t brightness = kBrightnessLevels[brightness_index];
      agentmeter::board_set_brightness(brightness);
      lv_label_set_text_fmt(button_label, "BUTTON OK  /  brightness %u",
                            brightness);
      Serial.printf("Button: pressed, brightness=%u\n", brightness);
    }
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
    Serial.println("Board: initialization failed; stopping diagnostic");
    return;
  }

  const uint32_t render_started_at_ms = millis();
  create_diagnostic_screen();
  lv_timer_handler();
  diagnostic_ready = true;
  Serial.printf("UI: first render scheduled in %u ms\n",
                millis() - render_started_at_ms);
}

void loop() {
  if (!diagnostic_ready) {
    delay(1000);
    return;
  }

  lv_timer_handler();
  update_button();

  const uint32_t now = millis();
  if (now - last_heartbeat_ms >= kHeartbeatIntervalMs) {
    last_heartbeat_ms = now;
    Serial.printf("Heartbeat: uptime=%lu s, heap=%u, minimum=%u\n",
                  static_cast<unsigned long>(now / 1000), ESP.getFreeHeap(),
                  ESP.getMinFreeHeap());
  }

  delay(5);
}
