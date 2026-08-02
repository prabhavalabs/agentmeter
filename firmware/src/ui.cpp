#include "ui.h"

#include <Arduino.h>
#include <lvgl.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <cstdio>
#include <cstring>

#include "boards/waveshare_amoled_216/board.h"
#include "settings_model.h"
#include "settings_store.h"
#include "ui_format.h"
#include "ui_layout.h"

namespace agentmeter {
namespace {

constexpr uint32_t kBackground = 0x070A12;
constexpr uint32_t kSurface = 0x111827;
constexpr uint32_t kSurfaceRaised = 0x182235;
constexpr uint32_t kBorder = 0x26344D;
constexpr uint32_t kText = 0xF4F7FF;
constexpr uint32_t kMuted = 0x8C9AB2;
constexpr uint32_t kGreen = 0x52E3B2;
constexpr uint32_t kAmber = 0xF5C451;
constexpr uint32_t kRed = 0xFF6B7A;
constexpr uint32_t kPurple = 0x8B7CFF;
constexpr uint32_t kBlue = 0x5EC8FF;
constexpr uint32_t kOrange = 0xF2A36B;

enum class ViewMode : uint8_t { Overview, Detail, Settings };

struct MetricWidgets {
  lv_obj_t* percent = nullptr;
  lv_obj_t* reset = nullptr;
  lv_obj_t* bar = nullptr;
  uint8_t provider_index = 0;
  uint8_t window_index = 0;
};

DashboardSnapshot model{};
DashboardPreferences preferences{};
bool has_model = false;
uint32_t model_received_at_ms = 0;
ConnectionState connection_state = ConnectionState::Waiting;
ViewMode view_mode = ViewMode::Overview;
uint8_t selected_provider = 0;
char advertised_name[24] = "AgentMeter";
std::array<char, kEventIdBytes> last_event_id{};

lv_obj_t* content = nullptr;
lv_obj_t* shift_layer = nullptr;
lv_obj_t* status_pill = nullptr;
lv_obj_t* status_label = nullptr;
lv_obj_t* status_pulse = nullptr;
lv_obj_t* subtitle_label = nullptr;
lv_obj_t* toast = nullptr;
lv_obj_t* rotation_value_label = nullptr;
std::array<MetricWidgets, kMaximumProviders> metrics{};
size_t metric_count = 0;

uint32_t last_dynamic_update_ms = 0;
uint32_t last_rotation_ms = 0;
uint32_t last_activity_ms = 0;
uint32_t last_pixel_shift_ms = 0;
uint8_t pixel_shift_index = 0;
bool dimmed = false;
bool screen_off = false;

lv_color_t color(uint32_t value) { return lv_color_hex(value); }

uint32_t provider_accent(const ProviderSnapshot& provider) {
  if (std::strcmp(provider.id.data(), "codex") == 0) {
    return kGreen;
  }
  if (std::strcmp(provider.id.data(), "claude") == 0) {
    return kOrange;
  }
  if (std::strcmp(provider.id.data(), "gemini") == 0) {
    return kBlue;
  }
  return kPurple;
}

const char* provider_status_text(ProviderStatus status) {
  switch (status) {
    case ProviderStatus::Ok:
      return "Available";
    case ProviderStatus::Stale:
      return "Data delayed";
    case ProviderStatus::Error:
      return "Unavailable";
    case ProviderStatus::Unavailable:
      return "Not signed in";
  }
  return "Unknown";
}

void set_plain_container(lv_obj_t* object) {
  lv_obj_set_style_bg_opa(object, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width(object, 0, 0);
  lv_obj_set_style_pad_all(object, 0, 0);
  lv_obj_remove_flag(object, LV_OBJ_FLAG_SCROLLABLE);
}

void style_surface(lv_obj_t* object) {
  lv_obj_set_style_bg_color(object, color(kSurface), 0);
  lv_obj_set_style_bg_opa(object, LV_OPA_COVER, 0);
  lv_obj_set_style_border_color(object, color(kBorder), 0);
  lv_obj_set_style_border_width(object, 1, 0);
  lv_obj_set_style_radius(object, 20, 0);
  lv_obj_set_style_pad_all(object, 0, 0);
  lv_obj_remove_flag(object, LV_OBJ_FLAG_SCROLLABLE);
}

lv_obj_t* label(lv_obj_t* parent, const char* text, int16_t x, int16_t y,
                const lv_font_t* font, uint32_t text_color = kText) {
  lv_obj_t* object = lv_label_create(parent);
  lv_label_set_text(object, text);
  lv_obj_set_pos(object, x, y);
  lv_obj_set_style_text_font(object, font, 0);
  lv_obj_set_style_text_color(object, color(text_color), 0);
  return object;
}

void set_content_scrolling(bool enabled) {
  lv_obj_scroll_to_y(content, 0, LV_ANIM_OFF);
  if (enabled) {
    lv_obj_add_flag(content, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scroll_dir(content, LV_DIR_VER);
    lv_obj_set_scrollbar_mode(content, LV_SCROLLBAR_MODE_AUTO);
  } else {
    lv_obj_remove_flag(content, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scrollbar_mode(content, LV_SCROLLBAR_MODE_OFF);
  }
}

lv_obj_t* add_icon_line(lv_obj_t* parent, const lv_point_precise_t* points,
                        uint32_t point_count, uint32_t line_color,
                        int16_t width = 2) {
  lv_obj_t* line_object = lv_line_create(parent);
  lv_line_set_points(line_object, points, point_count);
  lv_obj_set_style_line_color(line_object, color(line_color), 0);
  lv_obj_set_style_line_width(line_object, width, 0);
  lv_obj_set_style_line_rounded(line_object, true, 0);
  return line_object;
}

lv_obj_t* add_provider_icon(lv_obj_t* parent, const ProviderSnapshot& provider,
                            int16_t x, int16_t y, int16_t size) {
  const uint32_t accent = provider_accent(provider);
  lv_obj_t* icon = lv_obj_create(parent);
  lv_obj_set_pos(icon, x, y);
  lv_obj_set_size(icon, size, size);
  lv_obj_set_style_bg_color(icon, color(accent), 0);
  lv_obj_set_style_bg_opa(icon, LV_OPA_20, 0);
  lv_obj_set_style_border_width(icon, 0, 0);
  lv_obj_set_style_radius(icon, size / 2, 0);
  lv_obj_set_style_pad_all(icon, 0, 0);
  lv_obj_remove_flag(icon, LV_OBJ_FLAG_SCROLLABLE);

  if (std::strcmp(provider.id.data(), "codex") == 0) {
    for (int rotation : {0, 120, 240}) {
      lv_obj_t* arc = lv_arc_create(icon);
      lv_obj_set_size(arc, size - 11, size - 11);
      lv_obj_center(arc);
      lv_arc_set_bg_angles(arc, 38, 280);
      lv_arc_set_rotation(arc, rotation);
      lv_obj_set_style_arc_width(arc, 2, LV_PART_MAIN);
      lv_obj_set_style_arc_color(arc, color(accent), LV_PART_MAIN);
      lv_obj_set_style_arc_opa(arc, LV_OPA_COVER, LV_PART_MAIN);
      lv_obj_set_style_arc_width(arc, 0, LV_PART_INDICATOR);
      lv_obj_remove_flag(arc, LV_OBJ_FLAG_CLICKABLE);
    }
  } else if (std::strcmp(provider.id.data(), "claude") == 0) {
    static const lv_point_precise_t horizontal[] = {{5, 17}, {29, 17}};
    static const lv_point_precise_t vertical[] = {{17, 5}, {17, 29}};
    static const lv_point_precise_t diagonal_one[] = {{8, 8}, {26, 26}};
    static const lv_point_precise_t diagonal_two[] = {{26, 8}, {8, 26}};
    add_icon_line(icon, horizontal, 2, accent, 3);
    add_icon_line(icon, vertical, 2, accent, 3);
    add_icon_line(icon, diagonal_one, 2, accent, 3);
    add_icon_line(icon, diagonal_two, 2, accent, 3);
  } else if (std::strcmp(provider.id.data(), "gemini") == 0) {
    static const lv_point_precise_t sparkle[] = {
        {17, 4}, {21, 13}, {30, 17}, {21, 21}, {17, 30},
        {13, 21}, {4, 17}, {13, 13}, {17, 4}};
    add_icon_line(icon, sparkle, 9, accent, 2);
  } else {
    char initial[2] = {static_cast<char>(std::toupper(
                           static_cast<unsigned char>(provider.name[0]))),
                       '\0'};
    lv_obj_t* initial_label =
        label(icon, initial, 0, 0, &lv_font_montserrat_16, accent);
    lv_obj_center(initial_label);
  }
  return icon;
}

bool wake_for_input() {
  last_activity_ms = millis();
  if (!screen_off) {
    return false;
  }
  screen_off = false;
  dimmed = false;
  board_set_brightness(static_cast<uint8_t>(model.display.brightness_percent * 255 / 100));
  return true;
}

uint8_t urgent_window_index(const ProviderSnapshot& provider) {
  uint8_t selected = 0;
  int16_t highest = -1;
  for (uint8_t index = 0; index < provider.window_count; ++index) {
    if (provider.windows[index].used_percent > highest) {
      highest = provider.windows[index].used_percent;
      selected = index;
    }
  }
  return selected;
}

void refresh_metric(const MetricWidgets& widgets, int64_t now_epoch) {
  const ProviderSnapshot& provider = model.providers[widgets.provider_index];
  if (widgets.window_index >= provider.window_count) {
    return;
  }
  const QuotaWindow& window = provider.windows[widgets.window_index];
  char value[16] = {};
  format_usage_percent(window.used_percent, value, sizeof(value));
  lv_label_set_text(widgets.percent, value);
  lv_bar_set_value(widgets.bar, std::max<int16_t>(0, window.used_percent),
                   LV_ANIM_OFF);
  uint32_t bar_color = provider_accent(provider);
  if (window.used_percent >=
      model.display.alert_thresholds[model.display.alert_threshold_count - 1]) {
    bar_color = kRed;
  } else if (window.used_percent >= model.display.alert_thresholds[0]) {
    bar_color = kAmber;
  }
  lv_obj_set_style_bg_color(widgets.bar, color(bar_color), LV_PART_INDICATOR);
  if (window.has_reset) {
    char countdown[16] = {};
    format_countdown(seconds_until_reset(window.reset_at_epoch, now_epoch),
                     countdown, sizeof(countdown));
    lv_label_set_text_fmt(widgets.reset, "Resets in %s", countdown);
  } else {
    lv_label_set_text(widgets.reset, "Reset time unavailable");
  }
}

void refresh_dynamic_labels(uint32_t now_ms) {
  if (!has_model) {
    return;
  }
  const int64_t now_epoch =
      estimated_epoch(model, model_received_at_ms, now_ms);
  for (size_t index = 0; index < metric_count; ++index) {
    refresh_metric(metrics[index], now_epoch);
  }
  const uint32_t age_seconds = (now_ms - model_received_at_ms) / 1000U;
  if (age_seconds < 60) {
    lv_label_set_text(subtitle_label, "Updated moments ago");
  } else {
    lv_label_set_text_fmt(subtitle_label, "Updated %lu min ago",
                          static_cast<unsigned long>(age_seconds / 60));
  }
}

void update_connection_surface() {
  const char* text = "PAIRING";
  uint32_t foreground = kPurple;
  uint32_t background = 0x27224D;
  switch (connection_state) {
    case ConnectionState::Waiting:
      break;
    case ConnectionState::Connected:
      text = "LIVE";
      foreground = kGreen;
      background = 0x103C34;
      break;
    case ConnectionState::Reconnecting:
      text = "OFFLINE";
      foreground = kAmber;
      background = 0x463817;
      break;
    case ConnectionState::Stale:
      text = "STALE";
      foreground = kRed;
      background = 0x4A2028;
      break;
  }
  lv_label_set_text(status_label, text);
  lv_obj_set_style_text_color(status_label, color(foreground), 0);
  lv_obj_set_style_bg_color(status_pill, color(background), 0);
  lv_obj_set_style_bg_color(status_pulse, color(foreground), 0);
  if (content != nullptr) {
    lv_opa_t opacity = LV_OPA_COVER;
    if (view_mode != ViewMode::Settings &&
        connection_state == ConnectionState::Stale) {
      opacity = LV_OPA_50;
    } else if (view_mode != ViewMode::Settings &&
               connection_state == ConnectionState::Reconnecting) {
      opacity = LV_OPA_70;
    }
    lv_obj_set_style_opa(content, opacity, 0);
  }
}

void render_overview();
void render_detail();
void render_settings();
void show_toast(const char* message, uint32_t background);

void persist_preferences() {
  if (!save_dashboard_preferences(preferences)) {
    show_toast("Settings could not be saved", 0x642633);
  }
}

uint8_t first_visible_provider() {
  std::array<uint8_t, kMaximumProviders> visible{};
  return visible_provider_indices(model, preferences, visible) == 0
             ? kNoProviderIndex
             : visible[0];
}

void render_dashboard_home() {
  if (preferences.full_view) {
    if (selected_provider >= model.provider_count ||
        !is_provider_visible(preferences,
                             model.providers[selected_provider].id.data())) {
      selected_provider = first_visible_provider();
    }
    view_mode = ViewMode::Detail;
    render_detail();
  } else {
    view_mode = ViewMode::Overview;
    render_overview();
  }
}

void card_pressed(lv_event_t* event) {
  if (lv_event_get_code(event) != LV_EVENT_CLICKED || wake_for_input()) {
    return;
  }
  selected_provider = static_cast<uint8_t>(
      reinterpret_cast<uintptr_t>(lv_event_get_user_data(event)));
  view_mode = ViewMode::Detail;
  render_detail();
}

void back_pressed(lv_event_t* event) {
  if (lv_event_get_code(event) != LV_EVENT_CLICKED || wake_for_input()) {
    return;
  }
  render_dashboard_home();
  update_connection_surface();
}

void settings_pressed(lv_event_t* event) {
  if (lv_event_get_code(event) != LV_EVENT_CLICKED || wake_for_input()) {
    return;
  }
  view_mode = ViewMode::Settings;
  render_settings();
  update_connection_surface();
}

void add_overview_card(uint8_t provider_index, int16_t x, int16_t y,
                       int16_t width, int16_t height) {
  const ProviderSnapshot& provider = model.providers[provider_index];
  const uint32_t accent = provider_accent(provider);
  lv_obj_t* card = lv_obj_create(content);
  lv_obj_set_pos(card, x, y);
  lv_obj_set_size(card, width, height);
  style_surface(card);
  lv_obj_add_flag(card, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_add_event_cb(card, card_pressed, LV_EVENT_CLICKED,
                      reinterpret_cast<void*>(provider_index));

  lv_obj_t* accent_line = lv_obj_create(card);
  lv_obj_set_pos(accent_line, 0, 0);
  lv_obj_set_size(accent_line, 5, height);
  lv_obj_set_style_bg_color(accent_line, color(accent), 0);
  lv_obj_set_style_border_width(accent_line, 0, 0);
  lv_obj_set_style_radius(accent_line, 3, 0);

  lv_obj_t* name = label(card, provider.name.data(), 20, 16,
                         &lv_font_montserrat_20);
  lv_obj_set_width(name, width - 88);
  lv_label_set_long_mode(name, LV_LABEL_LONG_DOT);
  add_provider_icon(card, provider, width - 52, 12, 36);
  label(card, provider_status_text(provider.status), 20, 45,
        &lv_font_montserrat_14,
        provider.status == ProviderStatus::Ok ? kMuted : kAmber);

  if (provider.window_count == 0) {
    label(card, "--", 20, height - 82, &lv_font_montserrat_36, kMuted);
    label(card, "No quota data", 88, height - 70, &lv_font_montserrat_14,
          kMuted);
    return;
  }

  const uint8_t window_index = urgent_window_index(provider);
  const QuotaWindow& window = provider.windows[window_index];
  lv_obj_t* percent = label(card, "--", 20, height - 92,
                            &lv_font_montserrat_36);
  lv_obj_t* window_label = label(card, window.label.data(), 105, height - 78,
                                 &lv_font_montserrat_14, kMuted);
  lv_obj_set_width(window_label, width - 125);
  lv_label_set_long_mode(window_label, LV_LABEL_LONG_DOT);
  lv_obj_t* reset = label(card, "", 20, height - 43,
                          &lv_font_montserrat_14, kMuted);
  lv_obj_t* bar = lv_bar_create(card);
  lv_obj_set_pos(bar, 20, height - 17);
  lv_obj_set_size(bar, width - 40, 6);
  lv_bar_set_range(bar, 0, 100);
  lv_obj_set_style_bg_color(bar, color(kBorder), LV_PART_MAIN);
  lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, LV_PART_MAIN);
  lv_obj_set_style_bg_color(bar, color(accent), LV_PART_INDICATOR);
  lv_obj_set_style_radius(bar, 3, LV_PART_MAIN);
  lv_obj_set_style_radius(bar, 3, LV_PART_INDICATOR);
  metrics[metric_count++] =
      MetricWidgets{percent, reset, bar, provider_index, window_index};
}

void render_waiting() {
  metric_count = 0;
  lv_obj_clean(content);
  lv_obj_t* ring = lv_spinner_create(content);
  lv_obj_set_size(ring, 112, 112);
  lv_obj_align(ring, LV_ALIGN_TOP_MID, 0, 76);
  lv_obj_set_style_arc_color(ring, color(kBorder), LV_PART_MAIN);
  lv_obj_set_style_arc_color(ring, color(kPurple), LV_PART_INDICATOR);
  label(content, "Waiting for desktop", 0, 222, &lv_font_montserrat_28);
  lv_obj_t* title = lv_obj_get_child(content, -1);
  lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 222);
  label(content, advertised_name, 0, 270, &lv_font_montserrat_18, kPurple);
  lv_obj_t* name = lv_obj_get_child(content, -1);
  lv_obj_align(name, LV_ALIGN_TOP_MID, 0, 270);
  label(content, "Run: agentmeter send", 0, 318, &lv_font_montserrat_16,
        kMuted);
  lv_obj_t* instruction = lv_obj_get_child(content, -1);
  lv_obj_align(instruction, LV_ALIGN_TOP_MID, 0, 318);
}

void render_overview() {
  metric_count = 0;
  lv_obj_clean(content);
  set_content_scrolling(false);
  if (!has_model) {
    render_waiting();
    return;
  }
  std::array<uint8_t, kMaximumProviders> visible{};
  const uint8_t count =
      visible_provider_indices(model, preferences, visible);
  if (count == 0) {
    lv_obj_t* title = label(content, "No agents selected", 0, 118,
                            &lv_font_montserrat_28);
    lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 118);
    lv_obj_t* detail = label(content, "Choose agents in Settings", 0, 164,
                             &lv_font_montserrat_16, kMuted);
    lv_obj_align(detail, LV_ALIGN_TOP_MID, 0, 164);
    lv_obj_t* button = lv_button_create(content);
    lv_obj_set_size(button, 176, 52);
    lv_obj_align(button, LV_ALIGN_TOP_MID, 0, 220);
    lv_obj_set_style_bg_color(button, color(kPurple), 0);
    lv_obj_set_style_radius(button, 16, 0);
    lv_obj_add_event_cb(button, settings_pressed, LV_EVENT_CLICKED, nullptr);
    lv_obj_t* button_label = label(button, LV_SYMBOL_SETTINGS "  Settings",
                                   0, 0, &lv_font_montserrat_16);
    lv_obj_center(button_label);
    return;
  }
  set_content_scrolling(overview_content_height(count) > 398);
  for (uint8_t index = 0; index < count; ++index) {
    const CardFrame frame = overview_card_frame(count, index);
    add_overview_card(visible[index], frame.x, frame.y, frame.width,
                      frame.height);
  }
  refresh_dynamic_labels(millis());
}

void render_detail() {
  metric_count = 0;
  lv_obj_clean(content);
  set_content_scrolling(false);
  if (!has_model || selected_provider >= model.provider_count ||
      !is_provider_visible(preferences,
                           model.providers[selected_provider].id.data())) {
    render_overview();
    return;
  }
  const ProviderSnapshot& provider = model.providers[selected_provider];
  const uint32_t accent = provider_accent(provider);

  int16_t name_x = 128;
  if (preferences.full_view) {
    add_provider_icon(content, provider, 18, 10, 36);
    name_x = 70;
    lv_obj_t* rotation = lv_obj_create(content);
    lv_obj_set_pos(rotation, 354, 10);
    lv_obj_set_size(rotation, 108, 38);
    lv_obj_set_style_bg_color(rotation, color(kSurfaceRaised), 0);
    lv_obj_set_style_border_width(rotation, 0, 0);
    lv_obj_set_style_radius(rotation, 19, 0);
    lv_obj_set_style_pad_all(rotation, 0, 0);
    char rotation_text[20] = {};
    std::snprintf(rotation_text, sizeof(rotation_text), LV_SYMBOL_LOOP "  %us",
                  preferences.rotation_seconds);
    lv_obj_t* rotation_label =
        label(rotation, rotation_text, 0, 0, &lv_font_montserrat_14, kPurple);
    lv_obj_center(rotation_label);
  } else {
    lv_obj_t* back = lv_button_create(content);
    lv_obj_set_pos(back, 16, 8);
    lv_obj_set_size(back, 52, 52);
    lv_obj_set_style_bg_color(back, color(kSurfaceRaised), 0);
    lv_obj_set_style_radius(back, 16, 0);
    lv_obj_add_event_cb(back, back_pressed, LV_EVENT_CLICKED, nullptr);
    lv_obj_t* arrow =
        label(back, LV_SYMBOL_LEFT, 0, 0, &lv_font_montserrat_20);
    lv_obj_center(arrow);
    add_provider_icon(content, provider, 80, 16, 36);
  }

  lv_obj_t* name = label(content, provider.name.data(), name_x, 8,
                         &lv_font_montserrat_28);
  lv_obj_set_width(name, preferences.full_view ? 270 : 220);
  lv_label_set_long_mode(name, LV_LABEL_LONG_DOT);
  label(content, provider_status_text(provider.status), name_x + 2, 43,
        &lv_font_montserrat_14,
        provider.status == ProviderStatus::Ok ? kGreen : kAmber);

  if (provider.window_count == 0) {
    label(content, "No quota windows available", 34, 166,
          &lv_font_montserrat_20, kMuted);
    return;
  }

  for (uint8_t index = 0; index < provider.window_count; ++index) {
    const QuotaWindow& window = provider.windows[index];
    const int16_t y = 90 + index * 98;
    lv_obj_t* lane = lv_obj_create(content);
    lv_obj_set_pos(lane, 18, y);
    lv_obj_set_size(lane, 444, 88);
    style_surface(lane);
    label(lane, window.label.data(), 18, 13, &lv_font_montserrat_18);
    lv_obj_t* percent = label(lane, "--", 330, 8,
                              &lv_font_montserrat_28);
    lv_obj_set_width(percent, 90);
    lv_obj_set_style_text_align(percent, LV_TEXT_ALIGN_RIGHT, 0);
    lv_obj_t* reset = label(lane, "", 18, 43, &lv_font_montserrat_14,
                            kMuted);
    lv_obj_t* bar = lv_bar_create(lane);
    lv_obj_set_pos(bar, 18, 69);
    lv_obj_set_size(bar, 408, 6);
    lv_bar_set_range(bar, 0, 100);
    lv_obj_set_style_bg_color(bar, color(kBorder), LV_PART_MAIN);
    lv_obj_set_style_bg_color(bar, color(accent), LV_PART_INDICATOR);
    lv_obj_set_style_radius(bar, 3, LV_PART_MAIN);
    lv_obj_set_style_radius(bar, 3, LV_PART_INDICATOR);
    metrics[metric_count++] =
        MetricWidgets{percent, reset, bar, selected_provider, index};
  }
  refresh_dynamic_labels(millis());
}

lv_obj_t* add_settings_row(lv_obj_t* parent, int16_t y, const char* title,
                           const char* description) {
  lv_obj_t* row = lv_obj_create(parent);
  lv_obj_set_pos(row, 16, y);
  lv_obj_set_size(row, 448, 58);
  lv_obj_set_style_bg_color(row, color(kSurface), 0);
  lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
  lv_obj_set_style_border_color(row, color(kBorder), 0);
  lv_obj_set_style_border_width(row, 1, 0);
  lv_obj_set_style_radius(row, 16, 0);
  lv_obj_set_style_pad_all(row, 0, 0);
  lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);
  label(row, title, 62, 9, &lv_font_montserrat_16);
  label(row, description, 62, 33, &lv_font_montserrat_12, kMuted);
  return row;
}

lv_obj_t* add_settings_switch(lv_obj_t* row, bool checked,
                              lv_event_cb_t callback, void* user_data) {
  lv_obj_t* control = lv_switch_create(row);
  lv_obj_set_pos(control, 378, 15);
  lv_obj_set_size(control, 52, 28);
  lv_obj_set_style_bg_color(control, color(kBorder), LV_PART_MAIN);
  const lv_style_selector_t checked_indicator =
      static_cast<lv_style_selector_t>(LV_PART_INDICATOR) |
      static_cast<lv_style_selector_t>(LV_STATE_CHECKED);
  lv_obj_set_style_bg_color(control, color(kPurple), checked_indicator);
  if (checked) {
    lv_obj_add_state(control, LV_STATE_CHECKED);
  }
  lv_obj_add_event_cb(control, callback, LV_EVENT_VALUE_CHANGED, user_data);
  return control;
}

void provider_visibility_changed(lv_event_t* event) {
  if (wake_for_input()) {
    render_settings();
    return;
  }
  const uint8_t provider_index = static_cast<uint8_t>(
      reinterpret_cast<uintptr_t>(lv_event_get_user_data(event)));
  if (provider_index >= model.provider_count) {
    return;
  }
  lv_obj_t* control = static_cast<lv_obj_t*>(lv_event_get_target(event));
  const bool visible = lv_obj_has_state(control, LV_STATE_CHECKED);
  std::array<uint8_t, kMaximumProviders> visible_indices{};
  const uint8_t visible_count =
      visible_provider_indices(model, preferences, visible_indices);
  if (!visible && visible_count <= 1) {
    lv_obj_add_state(control, LV_STATE_CHECKED);
    show_toast("Keep at least one agent visible", 0x594617);
    return;
  }
  set_provider_visible(preferences, model.providers[provider_index].id.data(),
                       visible);
  persist_preferences();
  if (!visible && selected_provider == provider_index) {
    selected_provider = first_visible_provider();
  }
}

void always_on_changed(lv_event_t* event) {
  if (wake_for_input()) {
    render_settings();
    return;
  }
  lv_obj_t* control = static_cast<lv_obj_t*>(lv_event_get_target(event));
  preferences.always_on = lv_obj_has_state(control, LV_STATE_CHECKED);
  persist_preferences();
  last_activity_ms = millis();
  if (preferences.always_on) {
    screen_off = false;
    dimmed = false;
    board_set_brightness(
        static_cast<uint8_t>(model.display.brightness_percent * 255 / 100));
  }
}

void full_view_changed(lv_event_t* event) {
  if (wake_for_input()) {
    render_settings();
    return;
  }
  lv_obj_t* control = static_cast<lv_obj_t*>(lv_event_get_target(event));
  preferences.full_view = lv_obj_has_state(control, LV_STATE_CHECKED);
  last_rotation_ms = millis();
  persist_preferences();
}

void rotation_interval_changed(lv_event_t* event) {
  if (lv_event_get_code(event) != LV_EVENT_CLICKED || wake_for_input()) {
    return;
  }
  const int delta = static_cast<int>(
      reinterpret_cast<intptr_t>(lv_event_get_user_data(event)));
  const int next = static_cast<int>(preferences.rotation_seconds) + delta;
  if (next < kMinimumRotationSeconds || next > kMaximumRotationSeconds) {
    return;
  }
  set_rotation_seconds(preferences, static_cast<uint8_t>(next));
  last_rotation_ms = millis();
  persist_preferences();
  if (rotation_value_label != nullptr) {
    lv_label_set_text_fmt(rotation_value_label, "%u sec",
                          preferences.rotation_seconds);
  }
}

void render_settings() {
  metric_count = 0;
  rotation_value_label = nullptr;
  lv_obj_clean(content);
  set_content_scrolling(false);

  lv_obj_t* back = lv_button_create(content);
  lv_obj_set_pos(back, 16, 6);
  lv_obj_set_size(back, 48, 48);
  lv_obj_set_style_bg_color(back, color(kSurfaceRaised), 0);
  lv_obj_set_style_radius(back, 15, 0);
  lv_obj_add_event_cb(back, back_pressed, LV_EVENT_CLICKED, nullptr);
  lv_obj_t* arrow = label(back, LV_SYMBOL_LEFT, 0, 0, &lv_font_montserrat_18);
  lv_obj_center(arrow);
  label(content, "Settings", 78, 4, &lv_font_montserrat_28);
  label(content, "Saved on this display", 80, 39, &lv_font_montserrat_12,
        kMuted);

  lv_obj_t* list = lv_obj_create(content);
  lv_obj_set_pos(list, 0, 66);
  lv_obj_set_size(list, 480, 332);
  set_plain_container(list);
  lv_obj_add_flag(list, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_set_scroll_dir(list, LV_DIR_VER);
  lv_obj_set_scrollbar_mode(list, LV_SCROLLBAR_MODE_AUTO);
  lv_obj_set_style_pad_bottom(list, 16, 0);

  int16_t y = 4;
  label(list, "AGENT VISIBILITY", 22, y, &lv_font_montserrat_12, kMuted);
  y += 24;
  for (uint8_t index = 0; index < model.provider_count; ++index) {
    const ProviderSnapshot& provider = model.providers[index];
    lv_obj_t* row =
        add_settings_row(list, y, provider.name.data(), "Show on Home");
    add_provider_icon(row, provider, 14, 11, 36);
    add_settings_switch(
        row, is_provider_visible(preferences, provider.id.data()),
        provider_visibility_changed, reinterpret_cast<void*>(index));
    y += 64;
  }

  y += 8;
  label(list, "DISPLAY & FOCUS", 22, y, &lv_font_montserrat_12, kMuted);
  y += 24;

  lv_obj_t* always_on =
      add_settings_row(list, y, "Always on", "Disable automatic screen sleep");
  lv_obj_t* eye =
      label(always_on, LV_SYMBOL_EYE_OPEN, 0, 0, &lv_font_montserrat_18, kGreen);
  lv_obj_set_pos(eye, 24, 19);
  add_settings_switch(always_on, preferences.always_on, always_on_changed,
                      nullptr);
  y += 64;

  lv_obj_t* full_view = add_settings_row(
      list, y, "Full-view rotation", "Cycle through visible agents");
  lv_obj_t* loop =
      label(full_view, LV_SYMBOL_LOOP, 0, 0, &lv_font_montserrat_18, kPurple);
  lv_obj_set_pos(loop, 24, 19);
  add_settings_switch(full_view, preferences.full_view, full_view_changed,
                      nullptr);
  y += 64;

  lv_obj_t* interval = add_settings_row(
      list, y, "Rotation interval", "3 to 60 seconds per agent");
  lv_obj_t* clock =
      label(interval, LV_SYMBOL_REFRESH, 0, 0, &lv_font_montserrat_18, kBlue);
  lv_obj_set_pos(clock, 24, 19);
  lv_obj_t* minus = lv_button_create(interval);
  lv_obj_set_pos(minus, 278, 11);
  lv_obj_set_size(minus, 38, 36);
  lv_obj_set_style_bg_color(minus, color(kSurfaceRaised), 0);
  lv_obj_set_style_radius(minus, 12, 0);
  lv_obj_add_event_cb(minus, rotation_interval_changed, LV_EVENT_CLICKED,
                      reinterpret_cast<void*>(static_cast<intptr_t>(-1)));
  lv_obj_t* minus_label =
      label(minus, LV_SYMBOL_MINUS, 0, 0, &lv_font_montserrat_14);
  lv_obj_center(minus_label);
  rotation_value_label =
      label(interval, "", 318, 20, &lv_font_montserrat_14);
  lv_obj_set_width(rotation_value_label, 72);
  lv_obj_set_style_text_align(rotation_value_label, LV_TEXT_ALIGN_CENTER, 0);
  lv_label_set_text_fmt(rotation_value_label, "%u sec",
                        preferences.rotation_seconds);
  lv_obj_t* plus = lv_button_create(interval);
  lv_obj_set_pos(plus, 392, 11);
  lv_obj_set_size(plus, 38, 36);
  lv_obj_set_style_bg_color(plus, color(kSurfaceRaised), 0);
  lv_obj_set_style_radius(plus, 12, 0);
  lv_obj_add_event_cb(plus, rotation_interval_changed, LV_EVENT_CLICKED,
                      reinterpret_cast<void*>(static_cast<intptr_t>(1)));
  lv_obj_t* plus_label =
      label(plus, LV_SYMBOL_PLUS, 0, 0, &lv_font_montserrat_14);
  lv_obj_center(plus_label);
  y += 74;

  label(list, "Changes apply immediately and survive restarts.", 22, y,
        &lv_font_montserrat_12, kMuted);
  update_connection_surface();
}

void show_toast(const char* message, uint32_t background) {
  if (toast != nullptr) {
    lv_obj_delete(toast);
  }
  toast = lv_obj_create(lv_screen_active());
  lv_obj_add_event_cb(
      toast,
      [](lv_event_t* event) {
        if (lv_event_get_target(event) == toast) {
          toast = nullptr;
        }
      },
      LV_EVENT_DELETE, nullptr);
  lv_obj_set_size(toast, 380, 54);
  lv_obj_align(toast, LV_ALIGN_BOTTOM_MID, 0, -18);
  lv_obj_set_style_bg_color(toast, color(background), 0);
  lv_obj_set_style_border_width(toast, 0, 0);
  lv_obj_set_style_radius(toast, 18, 0);
  lv_obj_set_style_pad_all(toast, 0, 0);
  lv_obj_t* message_label = label(toast, message, 0, 0,
                                  &lv_font_montserrat_16);
  lv_obj_center(message_label);
  lv_obj_delete_delayed(toast, 8000);
}

void show_event(const DisplayEvent& event) {
  if (!event.present ||
      std::strcmp(event.id.data(), last_event_id.data()) == 0 ||
      event.expires_at_epoch < model.generated_at_epoch) {
    return;
  }
  std::snprintf(last_event_id.data(), last_event_id.size(), "%s",
                event.id.data());
  wake_for_input();

  char message[72] = "Usage alert";
  if (event.kind == EventKind::Threshold &&
      std::strncmp(event.id.data(), "threshold:", 10) == 0) {
    const char* provider_start = event.id.data() + 10;
    const char* provider_end = std::strchr(provider_start, ':');
    const char* threshold_start = std::strrchr(event.id.data(), ':');
    if (provider_end != nullptr && threshold_start != nullptr &&
        threshold_start > provider_end) {
      char provider_id[kDeviceTextBytes] = {};
      const size_t provider_length = std::min<size_t>(
          provider_end - provider_start, sizeof(provider_id) - 1);
      std::memcpy(provider_id, provider_start, provider_length);
      const char* provider_name = provider_id;
      for (uint8_t index = 0; index < model.provider_count; ++index) {
        if (std::strcmp(model.providers[index].id.data(), provider_id) == 0) {
          provider_name = model.providers[index].name.data();
          break;
        }
      }
      std::snprintf(message, sizeof(message), "%s reached %d%%", provider_name,
                    std::atoi(threshold_start + 1));
    }
  }
  show_toast(message, event.level == EventLevel::Critical ? 0x642633
                                                          : 0x594617);
  if (model.display.sound_enabled) {
    board_play_tone(event.level == EventLevel::Critical ? 1100 : 880, 120);
  }
}

}  // namespace

void ui_begin(const char* device_name) {
  std::snprintf(advertised_name, sizeof(advertised_name), "%s", device_name);
  load_dashboard_preferences(preferences);
  lv_obj_t* screen = lv_screen_active();
  lv_obj_set_style_bg_color(screen, color(kBackground), 0);
  lv_obj_set_style_text_color(screen, color(kText), 0);
  lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE);

  shift_layer = lv_obj_create(screen);
  lv_obj_set_pos(shift_layer, 0, 0);
  lv_obj_set_size(shift_layer, 480, 480);
  set_plain_container(shift_layer);

  label(shift_layer, "AgentMeter", 20, 15, &lv_font_montserrat_28);
  subtitle_label =
      label(shift_layer, "Private usage display", 22, 51,
            &lv_font_montserrat_14, kMuted);

  status_pill = lv_obj_create(shift_layer);
  lv_obj_set_pos(status_pill, 312, 20);
  lv_obj_set_size(status_pill, 102, 38);
  lv_obj_set_style_border_width(status_pill, 0, 0);
  lv_obj_set_style_radius(status_pill, 19, 0);
  lv_obj_set_style_pad_all(status_pill, 0, 0);
  status_pulse = lv_obj_create(status_pill);
  lv_obj_set_pos(status_pulse, 12, 14);
  lv_obj_set_size(status_pulse, 10, 10);
  lv_obj_set_style_border_width(status_pulse, 0, 0);
  lv_obj_set_style_radius(status_pulse, 5, 0);
  lv_obj_set_style_pad_all(status_pulse, 0, 0);
  lv_obj_remove_flag(status_pulse, LV_OBJ_FLAG_SCROLLABLE);
  status_label = label(status_pill, "PAIRING", 29, 10,
                       &lv_font_montserrat_14, kPurple);
  lv_obj_set_width(status_label, 66);
  lv_obj_set_style_text_align(status_label, LV_TEXT_ALIGN_CENTER, 0);

  lv_obj_t* settings = lv_button_create(shift_layer);
  lv_obj_set_pos(settings, 424, 19);
  lv_obj_set_size(settings, 40, 40);
  lv_obj_set_style_bg_color(settings, color(kSurfaceRaised), 0);
  lv_obj_set_style_radius(settings, 14, 0);
  lv_obj_add_event_cb(settings, settings_pressed, LV_EVENT_CLICKED, nullptr);
  lv_obj_t* settings_icon =
      label(settings, LV_SYMBOL_SETTINGS, 0, 0, &lv_font_montserrat_16, kMuted);
  lv_obj_center(settings_icon);

  content = lv_obj_create(shift_layer);
  lv_obj_set_pos(content, 0, 82);
  lv_obj_set_size(content, 480, 398);
  set_plain_container(content);

  last_activity_ms = millis();
  last_pixel_shift_ms = last_activity_ms;
  last_rotation_ms = last_activity_ms;
  update_connection_surface();
  render_waiting();
}

void ui_set_model(const DashboardSnapshot& snapshot, uint32_t received_at_ms) {
  const bool first_model = !has_model;
  model = snapshot;
  if (!model.event.present) {
    last_event_id[0] = '\0';
  }
  model_received_at_ms = received_at_ms;
  has_model = true;
  if (selected_provider >= model.provider_count ||
      !is_provider_visible(preferences,
                           model.providers[selected_provider].id.data())) {
    selected_provider = first_visible_provider();
  }
  if (first_model || preferences.always_on) {
    board_set_brightness(
        static_cast<uint8_t>(model.display.brightness_percent * 255 / 100));
    dimmed = false;
    screen_off = false;
    if (first_model) {
      last_activity_ms = millis();
    }
  }
  if (view_mode == ViewMode::Settings) {
    render_settings();
  } else if (preferences.full_view || view_mode == ViewMode::Detail) {
    view_mode = ViewMode::Detail;
    render_detail();
  } else {
    render_overview();
  }
  show_event(model.event);
}

void ui_set_connection(ConnectionState state) {
  if (connection_state == state) {
    return;
  }
  connection_state = state;
  update_connection_surface();
}

void ui_tick(uint32_t now_ms) {
  if (has_model && is_stale(model, model_received_at_ms, now_ms)) {
    ui_set_connection(ConnectionState::Stale);
  }
  if (now_ms - last_dynamic_update_ms >= 1000) {
    last_dynamic_update_ms = now_ms;
    refresh_dynamic_labels(now_ms);
  }

  if (status_pulse != nullptr) {
    const uint32_t phase = now_ms % 1200U;
    const uint8_t opacity = connection_state == ConnectionState::Connected
                                ? static_cast<uint8_t>(96 +
                                                       (phase < 600 ? phase
                                                                    : 1200 - phase) *
                                                           159 / 600)
                                : 255;
    lv_obj_set_style_opa(status_pulse, opacity, 0);
  }

  if (has_model && preferences.full_view && view_mode == ViewMode::Detail &&
      now_ms - last_rotation_ms >=
          static_cast<uint32_t>(preferences.rotation_seconds) * 1000U) {
    const uint8_t next =
        next_visible_provider(model, preferences, selected_provider);
    last_rotation_ms = now_ms;
    if (next != kNoProviderIndex && next != selected_provider) {
      selected_provider = next;
      render_detail();
    }
  }

  if (!preferences.always_on && !screen_off &&
      now_ms - last_activity_ms >= model.display.screen_off_after_seconds * 1000U) {
    screen_off = true;
    board_set_brightness(0);
  } else if (!preferences.always_on && !screen_off && !dimmed &&
             now_ms - last_activity_ms >= model.display.dim_after_seconds * 1000U) {
    dimmed = true;
    const uint8_t dim_level = static_cast<uint8_t>(
        std::max<int>(8, model.display.brightness_percent * 255 / 100 * 15 / 100));
    board_set_brightness(dim_level);
  }

  if (!screen_off && now_ms - last_pixel_shift_ms >= 60000) {
    last_pixel_shift_ms = now_ms;
    pixel_shift_index = (pixel_shift_index + 1) % 4;
    constexpr int8_t offsets[4][2] = {{0, 0}, {1, 0}, {1, 1}, {0, 1}};
    lv_obj_set_pos(shift_layer, offsets[pixel_shift_index][0],
                   offsets[pixel_shift_index][1]);
  }
}

void ui_toggle_view() {
  if (wake_for_input() || !has_model || model.provider_count == 0) {
    return;
  }
  if (view_mode == ViewMode::Settings) {
    render_dashboard_home();
    return;
  }
  if (preferences.full_view) {
    const uint8_t next =
        next_visible_provider(model, preferences, selected_provider);
    if (next != kNoProviderIndex) {
      selected_provider = next;
      last_rotation_ms = millis();
      view_mode = ViewMode::Detail;
      render_detail();
    }
    return;
  }
  if (view_mode == ViewMode::Overview) {
    selected_provider = first_visible_provider();
    if (selected_provider == kNoProviderIndex) {
      return;
    }
    view_mode = ViewMode::Detail;
    render_detail();
  } else {
    view_mode = ViewMode::Overview;
    render_overview();
  }
}

void ui_show_pairing_cleared() {
  wake_for_input();
  show_toast("Pairing cleared - ready to reconnect", 0x3B285F);
}

}  // namespace agentmeter
