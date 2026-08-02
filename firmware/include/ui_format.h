#pragma once

#include <cstddef>
#include <cstdint>

namespace agentmeter {

void format_usage_percent(int16_t used_percent, char* output,
                          size_t output_size);
void format_countdown(int64_t seconds, char* output, size_t output_size);

}  // namespace agentmeter
