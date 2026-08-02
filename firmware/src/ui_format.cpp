#include "ui_format.h"

#include <cstdio>

namespace agentmeter {

void format_usage_percent(int16_t used_percent, char* output,
                          size_t output_size) {
  if (used_percent < 0) {
    std::snprintf(output, output_size, "--");
  } else {
    std::snprintf(output, output_size, "%d%%", used_percent);
  }
}

void format_countdown(int64_t seconds, char* output, size_t output_size) {
  if (seconds <= 0) {
    std::snprintf(output, output_size, "now");
    return;
  }
  const int64_t days = seconds / 86400;
  if (days > 0) {
    std::snprintf(output, output_size, "%lldd",
                  static_cast<long long>(days));
    return;
  }
  const int64_t hours = seconds / 3600;
  const int64_t minutes = (seconds % 3600) / 60;
  if (hours > 0) {
    std::snprintf(output, output_size, "%lldh %lldm",
                  static_cast<long long>(hours),
                  static_cast<long long>(minutes));
  } else if (minutes > 0) {
    std::snprintf(output, output_size, "%lldm",
                  static_cast<long long>(minutes));
  } else {
    std::snprintf(output, output_size, "<1m");
  }
}

}  // namespace agentmeter
