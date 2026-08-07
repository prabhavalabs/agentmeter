import AgentMeterCore
import Testing
@testable import AgentMeterUI

@Test func providerPaletteMatchesTheDevicePalette() {
    #expect(ProviderPalette.accentHex(for: "codex") == 0x3DDC97)
    #expect(ProviderPalette.accentHex(for: "claude") == 0xF4A261)
    #expect(ProviderPalette.accentHex(for: "gemini") == 0x6FA8FF)
    #expect(ProviderPalette.accentHex(for: "cursor") == 0xD8D8DC)
    #expect(ProviderPalette.accentHex(for: "future-agent") == 0x8B7CFF)
}

@Test func providerPaletteDelegatesToSharedProviderVisuals() {
    for providerId in ["codex", "claude", "gemini", "cursor", "future-agent"] {
        #expect(ProviderPalette.accentHex(for: providerId) == ProviderVisuals.accentHex(for: providerId))
    }
}

@MainActor
@Test func everyAppearanceHasAnExplicitPolicy() {
    #expect(AppearancePreference.system.colorScheme == nil)
    #expect(AppearancePreference.light.colorScheme != nil)
    #expect(AppearancePreference.dark.colorScheme != nil)
}

@Test func providerCardsKeepOneHeightAcrossSupportedWindowCounts() {
    let heights = (0...3).map { ProviderCardLayout.height(windowCount: $0) }

    #expect(Set(heights).count == 1)
    #expect(heights.allSatisfy { $0 >= 260 })
}

@Test func menuNavigationLabelsAreDistinctAndCompact() {
    let titles = NavigationSection.allCases.map(\.menuTitle)

    #expect(Set(titles).count == NavigationSection.allCases.count)
    #expect(titles.allSatisfy { $0.isEmpty == false })
    #expect(titles.allSatisfy { $0.count <= 24 })
}
