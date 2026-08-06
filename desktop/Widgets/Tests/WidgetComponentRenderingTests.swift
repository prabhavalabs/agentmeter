import AgentMeterCore
import AgentMeterWidgetCore
import AppKit
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
    guard let image else { return }
    let substance = renderedSubstance(image)
    #expect(substance.nontransparentRatio >= 0.05)
    #expect(substance.distinctColorCount >= 6)
}

@MainActor
private func renderedSubstance(_ image: NSImage) -> (nontransparentRatio: Double, distinctColorCount: Int) {
    guard let data = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: data),
          bitmap.pixelsWide > 0,
          bitmap.pixelsHigh > 0 else {
        return (0, 0)
    }
    let stride = max(1, min(bitmap.pixelsWide, bitmap.pixelsHigh) / 100)
    var sampled = 0
    var nontransparent = 0
    var colors = Set<UInt32>()

    for y in Swift.stride(from: 0, to: bitmap.pixelsHigh, by: stride) {
        for x in Swift.stride(from: 0, to: bitmap.pixelsWide, by: stride) {
            sampled += 1
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            guard color.alphaComponent >= 0.05 else { continue }
            nontransparent += 1
            let red = UInt32((color.redComponent * 15).rounded())
            let green = UInt32((color.greenComponent * 15).rounded())
            let blue = UInt32((color.blueComponent * 15).rounded())
            let alpha = UInt32((color.alphaComponent * 15).rounded())
            colors.insert((red << 12) | (green << 8) | (blue << 4) | alpha)
        }
    }
    return (Double(nontransparent) / Double(max(sampled, 1)), colors.count)
}

@Test func innerRingLegendUsesDisplayedPercentAndExactUnknownCopy() {
    let known = WidgetRingPresentation(
        windowKind: "session",
        label: "Session",
        usedPercent: 24,
        displayedPercent: 76,
        resetState: .scheduled(epoch: 1_800_000_000)
    )
    let unknown = WidgetRingPresentation(
        windowKind: "session",
        label: "Session",
        usedPercent: nil,
        displayedPercent: nil,
        resetState: .unavailable
    )

    #expect(DualUsageRingLegend.innerText(known) == "Session 76%")
    #expect(DualUsageRingLegend.innerText(unknown) == "Session Not reported")
}

@Test func historyAccessibilityDescriptionsExposeEveryDateValueAndGap() {
    let zero = WidgetHeatMapCell(dayStartEpoch: 0, value: 0, band: .zero)
    let heatGap = WidgetHeatMapCell(dayStartEpoch: 86_400, value: nil, band: nil)
    let trendValue = WidgetTrendPoint(dayStartEpoch: 172_800, latestUsedPercent: 42)
    let trendGap = WidgetTrendPoint(dayStartEpoch: 259_200, latestUsedPercent: nil)

    #expect(WidgetHistoryAccessibility.heatMapDay(zero).contains("0 allowance percentage points consumed"))
    #expect(WidgetHistoryAccessibility.heatMapDay(heatGap).contains("No allowance consumption reported"))
    #expect(WidgetHistoryAccessibility.trendDay(trendValue).contains("42 percent used"))
    #expect(WidgetHistoryAccessibility.trendDay(trendGap).contains("Used allowance not reported"))
    #expect(WidgetHistoryAccessibility.heatMapDay(zero).contains("1970"))
    #expect(WidgetHistoryAccessibility.heatMapDay(heatGap).contains("1970"))
    #expect(WidgetHistoryAccessibility.trendDay(trendValue).contains("1970"))
    #expect(WidgetHistoryAccessibility.trendDay(trendGap).contains("1970"))
    #expect(WidgetHistoryAccessibility.heatMapDay(zero) != WidgetHistoryAccessibility.heatMapDay(heatGap))
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
