import AgentMeterCore
import AgentMeterWidgetCore
import SwiftUI
import Testing

@Test func everyProviderAccentMeetsNonTextContrastInLightAndDarkThemes() {
    let providers = ["codex", "claude", "gemini", "cursor"]
    let themes: [WidgetTheme] = [
        .system,
        .light,
        .dark,
        .midnight,
        .neutral,
        .providerTinted,
    ]

    for providerID in providers {
        let base = WidgetRGB(hex: ProviderVisuals.accentHex(for: providerID))
        for requestedScheme in [ColorScheme.light, .dark] {
            for theme in themes {
                let background = WidgetThemeContrastModel.background(
                    theme: theme,
                    requestedScheme: requestedScheme,
                    providerBaseAccent: base
                )
                let resolved = WidgetAccentResolver.resolve(
                    base: base,
                    against: background,
                    scheme: WidgetThemeContrastModel.effectiveScheme(
                        theme: theme,
                        requestedScheme: requestedScheme
                    )
                )

                #expect(resolved.contrastRatio(against: background) >= 3.0)
            }
        }
    }
}

@Test func approvedThemeContainerBaselinesRemainDistinct() {
    let base = WidgetRGB(hex: ProviderVisuals.accentHex(for: "codex"))
    for scheme in [ColorScheme.light, .dark] {
        let backgrounds = [WidgetTheme.system, .midnight, .neutral, .providerTinted].map {
            WidgetThemeContrastModel.background(
                theme: $0,
                requestedScheme: scheme,
                providerBaseAccent: base
            )
        }
        #expect(Set(backgrounds).count == backgrounds.count)
    }
}
