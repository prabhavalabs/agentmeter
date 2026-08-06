import AgentMeterCore
import AgentMeterWidgetCore
import Foundation
import SwiftUI
import Testing

@Test func dataAccentSourcesNeverReduceResolvedColorsWithOpacity() throws {
    let widgetDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourcePaths = [
        "Sources/Components/DualUsageRing.swift",
        "Sources/Components/UsageHeatMap.swift",
        "Sources/Components/UsageTrendChart.swift",
        "Sources/Components/WidgetProviderMark.swift",
        "Sources/Focus/FocusWidgetView.swift",
        "Sources/Dashboard/DashboardWidgetView.swift",
        "Sources/Dashboard/DashboardProviderRow.swift",
        "Sources/Dashboard/DashboardHistoryPanel.swift",
    ]
    let opacityPattern = try NSRegularExpression(
        pattern: #"(?:\b(?:accent|color|[A-Za-z0-9_]*Accent)\b|dataAccent\([^)]*\))\s*\.\s*opacity\s*\("#
    )

    for sourcePath in sourcePaths {
        let source = try String(
            contentsOf: widgetDirectory.appendingPathComponent(sourcePath),
            encoding: .utf8
        )
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        #expect(opacityPattern.firstMatch(in: source, range: range) == nil)
    }
}

@Test func everyFinalDataAccentMeetsNonTextContrastInLightAndDarkThemes() {
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
                let dataAccents = WidgetThemeContrastModel.dataAccents(
                    theme: theme,
                    requestedScheme: requestedScheme,
                    providerBaseAccent: base
                )

                for role in WidgetDataAccentRole.allCases {
                    #expect(dataAccents[role].contrastRatio(against: background) >= 3.0)
                }
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
