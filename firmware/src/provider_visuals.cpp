#include "provider_visuals.h"

#include <cstring>

namespace agentmeter {

ProviderVisuals provider_visuals(const char* provider_id) {
  if (std::strcmp(provider_id, "codex") == 0) {
    return ProviderVisuals{0x3DDC97, ProviderMark::Codex};
  }
  if (std::strcmp(provider_id, "claude") == 0) {
    return ProviderVisuals{0xF4A261, ProviderMark::Claude};
  }
  if (std::strcmp(provider_id, "gemini") == 0) {
    return ProviderVisuals{0x6FA8FF, ProviderMark::Gemini};
  }
  if (std::strcmp(provider_id, "cursor") == 0) {
    return ProviderVisuals{0xD8D8DC, ProviderMark::CursorCube};
  }
  return ProviderVisuals{0x8B7CFF, ProviderMark::Initial};
}

}  // namespace agentmeter
