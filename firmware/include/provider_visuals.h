#pragma once

#include <cstdint>

namespace agentmeter {

enum class ProviderMark : uint8_t {
  Initial,
  Codex,
  Claude,
  Gemini,
  CursorCube,
};

struct ProviderVisuals {
  uint32_t accent_rgb;
  ProviderMark mark;
};

ProviderVisuals provider_visuals(const char* provider_id);

}  // namespace agentmeter
