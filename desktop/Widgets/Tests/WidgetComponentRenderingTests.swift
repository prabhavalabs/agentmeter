import AgentMeterCore
import AgentMeterWidgetCore
import SwiftUI
import Testing
import WidgetKit

@MainActor
@Test(arguments: [ColorScheme.light, .dark])
func dualUsageRingRendersInAdaptiveAppearances(colorScheme: ColorScheme) {
    let outer = WidgetRingPresentation(
        windowKind: "weekly",
        label: "Weekly",
        usedPercent: 42,
        displayedPercent: 42,
        resetState: .scheduled(epoch: 1_800_000_000)
    )
    let inner = WidgetRingPresentation(
        windowKind: "session",
        label: "Session",
        usedPercent: nil,
        displayedPercent: nil,
        resetState: .unavailable
    )

    assertRendered(
        DualUsageRing(outer: outer, inner: inner, accent: Color.mint, percentageMode: .used),
        size: CGSize(width: 180, height: 180),
        colorScheme: colorScheme
    )
}

@MainActor
@Test(arguments: [ColorScheme.light, .dark])
func usageHistoryViewsRenderGapsAndZeroInAdaptiveAppearances(colorScheme: ColorScheme) {
    let projection = WidgetHistoryProjection(
        cells: [
            WidgetHeatMapCell(dayStartEpoch: 0, value: nil, band: nil),
            WidgetHeatMapCell(dayStartEpoch: 86_400, value: 0, band: .zero),
            WidgetHeatMapCell(dayStartEpoch: 172_800, value: 31, band: .veryHigh),
        ],
        trendPoints: [
            WidgetTrendPoint(dayStartEpoch: 0, latestUsedPercent: 12),
            WidgetTrendPoint(dayStartEpoch: 86_400, latestUsedPercent: nil),
            WidgetTrendPoint(dayStartEpoch: 172_800, latestUsedPercent: 64),
        ],
        windowKind: "weekly",
        windowLabel: "Weekly"
    )

    assertRendered(
        UsageHeatMap(projection: projection, accent: Color.mint),
        size: CGSize(width: 320, height: 120),
        colorScheme: colorScheme
    )
    assertRendered(
        UsageTrendChart(projection: projection, accent: Color.mint),
        size: CGSize(width: 320, height: 160),
        colorScheme: colorScheme
    )
}

@MainActor
@Test(arguments: [
    (AgentMeterWidgetCore.WidgetFamily.small, CGSize(width: 170, height: 170)),
    (.medium, CGSize(width: 360, height: 170)),
    (.large, CGSize(width: 360, height: 380)),
    (.extraLarge, CGSize(width: 720, height: 380)),
])
func focusWidgetRendersAtEveryFamily(family: AgentMeterWidgetCore.WidgetFamily, size: CGSize) {
    for colorScheme in [ColorScheme.light, .dark] {
        assertRendered(
            FocusWidgetView(presentation: renderingPresentation(family: family)),
            size: size,
            colorScheme: colorScheme
        )
    }
}

@MainActor
private func assertRendered<V: View>(
    _ view: V,
    size: CGSize,
    colorScheme: ColorScheme
) {
    let renderer = ImageRenderer(
        content: view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, colorScheme)
    )
    renderer.proposedSize = ProposedViewSize(size)
    renderer.scale = 1

    let image = renderer.nsImage
    #expect(image != nil)
    #expect((image?.size.width ?? 0) > 0)
    #expect((image?.size.height ?? 0) > 0)
}

private func renderingPresentation(family: AgentMeterWidgetCore.WidgetFamily) -> WidgetPresentation {
    let configuration = WidgetRenderConfiguration(
        kind: .focus,
        providerIDs: ["codex"],
        focusProviderID: "codex",
        outerWindowKind: "weekly",
        innerWindowKind: "session",
        percentageMode: .used,
        modules: [.usage, .primaryReset, .history, .status, .freshness],
        historyStyle: .trend,
        historyPeriod: .days7,
        heatMapScope: .singleProvider,
        layout: .automatic,
        density: .comfortable,
        theme: .providerTinted,
        tapDestination: .providerDetail,
        showsResetCountdown: true,
        showsAbsoluteResetDate: true
    )
    let outer = WidgetRingPresentation(
        windowKind: "weekly",
        label: "Weekly",
        usedPercent: 42,
        displayedPercent: 42,
        resetState: .scheduled(epoch: 1_800_000_000)
    )
    let inner = WidgetRingPresentation(
        windowKind: "session",
        label: "Session",
        usedPercent: nil,
        displayedPercent: nil,
        resetState: .unavailable
    )
    return WidgetPresentation(
        configuration: configuration,
        family: family,
        providers: [
            WidgetProviderPresentation(
                id: "codex",
                name: "Codex",
                status: "Ready",
                rings: [outer, inner],
                additionalWindows: [
                    WidgetRingPresentation(
                        windowKind: "model",
                        label: "GPT-5",
                        usedPercent: 18,
                        displayedPercent: 18,
                        resetState: .pending
                    ),
                ]
            ),
        ],
        modules: configuration.modules,
        history: WidgetHistoryProjection(
            cells: [],
            trendPoints: [
                WidgetTrendPoint(dayStartEpoch: 0, latestUsedPercent: 12),
                WidgetTrendPoint(dayStartEpoch: 86_400, latestUsedPercent: nil),
                WidgetTrendPoint(dayStartEpoch: 172_800, latestUsedPercent: 42),
            ],
            windowKind: "weekly",
            windowLabel: "Weekly"
        ),
        freshness: .stale,
        overflowCount: 0
    )
}
