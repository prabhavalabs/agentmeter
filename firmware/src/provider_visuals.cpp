#include "provider_visuals.h"

#include <cstring>

namespace agentmeter {

ProviderVisuals provider_visuals(const char* provider_id) {
  if (std::strcmp(provider_id, "codex") == 0) {
    return ProviderVisuals{0x52E3B2, ProviderMark::Codex};
  }
  if (std::strcmp(provider_id, "claude") == 0) {
    return ProviderVisuals{0xF2A36B, ProviderMark::Claude};
  }
  if (std::strcmp(provider_id, "gemini") == 0) {
    return ProviderVisuals{0x5EC8FF, ProviderMark::Gemini};
  }
  if (std::strcmp(provider_id, "cursor") == 0) {
    return ProviderVisuals{0xD6D5CC, ProviderMark::CursorCube};
  }
  return ProviderVisuals{0x8B7CFF, ProviderMark::Initial};
}

}  // namespace agentmeter
