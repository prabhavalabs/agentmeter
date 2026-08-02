#include "ui.h"

#include <Arduino.h>
#include <lvgl.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstdio>
#include <cstring>

#include "boards/waveshare_amoled_216/board.h"
#include "ui_format.h"

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

enum class ViewMode : uint8_t { Overview, Detail };

struct MetricWidgets {
  lv_obj_t* percent = nullptr;
  lv_obj_t* reset = nullptr;
  lv_obj_t* bar = nullptr;
  uint8_t provider_index = 0;
  uint8_t window_index = 0;
};

DashboardSnapshot model{};
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
lv_obj_t* subtitle_label = nullptr;
lv_obj_t* toast = nullptr;
std::array<MetricWidgets, kMaximumProviders> metrics{};
size_t metric_count = 0;

uint32_t last_dynamic_update_ms = 0;
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
  if (content != nullptr) {
    const lv_opa_t opacity =
        connection_state == ConnectionState::Stale
            ? LV_OPA_50
            : (connection_state == ConnectionState::Reconnecting ? LV_OPA_70
                                                                  : LV_OPA_COVER);
    lv_obj_set_style_opa(content, opacity, 0);
  }
}

void render_overview();
void render_detail();

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
  view_mode = ViewMode::Overview;
  render_overview();
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
  lv_obj_set_width(name, width - 42);
  lv_label_set_long_mode(name, LV_LABEL_LONG_DOT);
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
  if (!has_model) {
    render_waiting();
    return;
  }
  const uint8_t count = model.provider_count;
  if (count == 1) {
    add_overview_card(0, 20, 20, 440, 340);
  } else if (count == 2) {
    add_overview_card(0, 20, 10, 440, 176);
    add_overview_card(1, 20, 196, 440, 176);
  } else {
    for (uint8_t index = 0; index < count; ++index) {
      const int16_t x = index % 2 == 0 ? 14 : 247;
      const int16_t y = index < 2 ? 8 : 198;
      add_overview_card(index, x, y, 219, 180);
    }
  }
  refresh_dynamic_labels(millis());
}

void render_detail() {
  metric_count = 0;
  lv_obj_clean(content);
  if (!has_model || selected_provider >= model.provider_count) {
    render_overview();
    return;
  }
  const ProviderSnapshot& provider = model.providers[selected_provider];
  const uint32_t accent = provider_accent(provider);

  lv_obj_t* back = lv_button_create(content);
  lv_obj_set_pos(back, 16, 8);
  lv_obj_set_size(back, 52, 52);
  lv_obj_set_style_bg_color(back, color(kSurfaceRaised), 0);
  lv_obj_set_style_radius(back, 16, 0);
  lv_obj_add_event_cb(back, back_pressed, LV_EVENT_CLICKED, nullptr);
  lv_obj_t* arrow = label(back, LV_SYMBOL_LEFT, 0, 0, &lv_font_montserrat_20);
  lv_obj_center(arrow);

  lv_obj_t* name = label(content, provider.name.data(), 84, 8,
                         &lv_font_montserrat_28);
  lv_obj_set_width(name, 280);
  lv_label_set_long_mode(name, LV_LABEL_LONG_DOT);
  label(content, provider_status_text(provider.status), 86, 43,
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
  lv_obj_set_pos(status_pill, 366, 22);
  lv_obj_set_size(status_pill, 94, 34);
  lv_obj_set_style_border_width(status_pill, 0, 0);
  lv_obj_set_style_radius(status_pill, 17, 0);
  lv_obj_set_style_pad_all(status_pill, 0, 0);
  status_label = label(status_pill, "PAIRING", 0, 0,
                       &lv_font_montserrat_14, kPurple);
  lv_obj_center(status_label);

  content = lv_obj_create(shift_layer);
  lv_obj_set_pos(content, 0, 82);
  lv_obj_set_size(content, 480, 398);
  set_plain_container(content);

  last_activity_ms = millis();
  last_pixel_shift_ms = last_activity_ms;
  update_connection_surface();
  render_waiting();
}

void ui_set_model(const DashboardSnapshot& snapshot, uint32_t received_at_ms) {
  model = snapshot;
  if (!model.event.present) {
    last_event_id[0] = '\0';
  }
  model_received_at_ms = received_at_ms;
  has_model = true;
  if (selected_provider >= model.provider_count) {
    selected_provider = 0;
    view_mode = ViewMode::Overview;
  }
  board_set_brightness(
      static_cast<uint8_t>(model.display.brightness_percent * 255 / 100));
  dimmed = false;
  screen_off = false;
  last_activity_ms = millis();
  if (view_mode == ViewMode::Detail) {
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

  if (!screen_off &&
      now_ms - last_activity_ms >= model.display.screen_off_after_seconds * 1000U) {
    screen_off = true;
    board_set_brightness(0);
  } else if (!screen_off && !dimmed &&
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
  if (view_mode == ViewMode::Overview) {
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
