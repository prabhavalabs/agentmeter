import AgentMeterUI
import Testing

@Test func providerPaletteMatchesTheDevicePalette() {
    #expect(ProviderPalette.accentHex(for: "codex") == 0x52E3B2)
    #expect(ProviderPalette.accentHex(for: "claude") == 0xF2A36B)
    #expect(ProviderPalette.accentHex(for: "gemini") == 0x5EC8FF)
    #expect(ProviderPalette.accentHex(for: "cursor") == 0xD6D5CC)
    #expect(ProviderPalette.accentHex(for: "future-agent") == 0x8B7CFF)
}

@MainActor
@Test func everyAppearanceHasAnExplicitPolicy() {
    #expect(AppearancePreference.system.colorScheme == nil)
    #expect(AppearancePreference.light.colorScheme != nil)
    #expect(AppearancePreference.dark.colorScheme != nil)
}
