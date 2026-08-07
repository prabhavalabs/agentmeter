import AgentMeterCore
import AgentMeterWidgetCore
import AppKit
import SwiftUI
import Testing
import WidgetKit

private func testPalette() -> WidgetThemePalette {
    WidgetThemePalette(theme: .system, providerID: "codex", colorScheme: .dark)
}

@MainActor
@Test(arguments: [ColorScheme.light, .dark])
func singleUsageRingRendersKnownAndUnknownInAdaptiveAppearances(colorScheme: ColorScheme) {
    assertRendered(
        SingleUsageRing(
            displayedPercent: 42,
            accent: Color.mint,
            track: Color.gray.opacity(0.3),
            glows: true
        ) {
            Text("42%").font(.system(size: 20, weight: .bold)).monospacedDigit()
        }
        .frame(width: 120, height: 120),
        size: CGSize(width: 160, height: 160),
        colorScheme: colorScheme
    )
    assertRendered(
        SingleUsageRing(
            displayedPercent: nil,
            accent: Color.mint,
            track: Color.gray.opacity(0.3)
        ) {
            Text("—").font(.system(size: 20, weight: .bold))
        }
        .frame(width: 120, height: 120),
        size: CGSize(width: 160, height: 160),
        colorScheme: colorScheme
    )
}

/// A nil percent must never be drawn like a zero percent: the ring falls back
/// to a dashed track, the bar row hatches its track and says "Not reported".
@MainActor
@Test func nilPercentNeverRendersLikeZeroInRingAndBar() throws {
    let palette = testPalette()
    let ringSize = CGSize(width: 120, height: 120)
    let ringDifference = renderedDifferenceRatio(
        SingleUsageRing(displayedPercent: nil, accent: Color.mint, track: Color.gray) {
            EmptyView()
        },
        SingleUsageRing(displayedPercent: 0, accent: Color.mint, track: Color.gray) {
            EmptyView()
        },
        size: ringSize,
        region: CGRect(origin: .zero, size: ringSize)
    )
    #expect(ringDifference > 0.005)

    let barSize = CGSize(width: 220, height: 40)
    let barDifference = renderedDifferenceRatio(
        UsageBarRow(
            label: "Session",
            displayedPercent: nil,
            accent: Color.mint,
            palette: palette
        ),
        UsageBarRow(
            label: "Session",
            displayedPercent: 0,
            accent: Color.mint,
            palette: palette
        ),
        size: barSize,
        region: CGRect(origin: .zero, size: barSize)
    )
    #expect(barDifference > 0.005)

    let barSource = try String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Components/UsageBarRow.swift"),
        encoding: .utf8
    )
    #expect(barSource.contains("\"Not reported\""))
}

@MainActor
@Test(arguments: [ColorScheme.light, .dark])
func usageHistoryComponentsRenderGapsAndZeroInAdaptiveAppearances(colorScheme: ColorScheme) {
    let palette = testPalette()
    let cells = [
        WidgetHeatMapCell(dayStartEpoch: 0, value: nil, band: nil),
        WidgetHeatMapCell(dayStartEpoch: 86_400, value: 0, band: .zero),
        WidgetHeatMapCell(dayStartEpoch: 172_800, value: 4, band: .low),
        WidgetHeatMapCell(dayStartEpoch: 259_200, value: 12, band: .moderate),
        WidgetHeatMapCell(dayStartEpoch: 345_600, value: 22, band: .high),
        WidgetHeatMapCell(dayStartEpoch: 432_000, value: 31, band: .veryHigh),
    ]

    assertRendered(
        VStack(spacing: 8) {
            ConsumptionStrip(cells: cells, accent: Color.mint, palette: palette, cellHeight: 12)
            ConsumptionStrip(
                cells: cells,
                accent: Color.mint,
                palette: palette,
                cellHeight: 16,
                cornerRadius: 5,
                columns: 3
            )
        },
        size: CGSize(width: 320, height: 120),
        colorScheme: colorScheme
    )
    assertRendered(
        UsageTrendChart(
            trendPoints: [
                WidgetTrendPoint(dayStartEpoch: 0, latestUsedPercent: 12),
                WidgetTrendPoint(dayStartEpoch: 86_400, latestUsedPercent: nil),
                WidgetTrendPoint(dayStartEpoch: 172_800, latestUsedPercent: 64),
                WidgetTrendPoint(dayStartEpoch: 259_200, latestUsedPercent: 48),
            ],
            accent: Color.mint,
            palette: palette
        ),
        size: CGSize(width: 320, height: 50),
        colorScheme: colorScheme
    )
    assertRendered(
        HourlyTrendChart(
            series: [
                HourlyTrendSeries(
                    id: "codex",
                    name: "Codex",
                    accent: Color.mint,
                    points: (0..<24).map {
                        WidgetHourlyPoint(
                            providerId: "codex",
                            windowKind: "weekly",
                            hourStartEpoch: $0 * 3_600,
                            latestUsedPercent: min(100, 10 + $0 * 3),
                            resetAtEpoch: nil
                        )
                    }
                ),
                HourlyTrendSeries(
                    id: "claude",
                    name: "Claude",
                    accent: Color.orange,
                    points: (0..<24).map {
                        WidgetHourlyPoint(
                            providerId: "claude",
                            windowKind: "monthly",
                            hourStartEpoch: $0 * 3_600,
                            latestUsedPercent: max(0, 80 - $0 * 2),
                            resetAtEpoch: nil
                        )
                    }
                ),
            ],
            palette: palette,
            height: 46,
            showsYAxis: true
        ),
        size: CGSize(width: 320, height: 70),
        colorScheme: colorScheme
    )
}

@MainActor
@Test(arguments: [ColorScheme.light, .dark])
func statusIndicatorsRenderInAdaptiveAppearances(colorScheme: ColorScheme) {
    assertRendered(
        HStack(spacing: 10) {
            StatusDot(health: .healthy, worstUsedPercent: 20, size: 10)
            StatusDot(health: .healthy, worstUsedPercent: 80, size: 10)
            StatusDot(health: .error, worstUsedPercent: nil, size: 10)
            StatusDot(health: .stale, worstUsedPercent: nil, size: 10, glows: false)
            LivePill(freshness: .fresh)
            LivePill(freshness: .stale)
        },
        size: CGSize(width: 240, height: 40),
        colorScheme: colorScheme
    )
}

@MainActor
@Test func statusDotDistinguishesPressureAndHealthTiers() {
    let size = CGSize(width: 24, height: 24)
    let region = CGRect(origin: .zero, size: size)
    #expect(renderedDifferenceRatio(
        StatusDot(health: .healthy, worstUsedPercent: 20, size: 14),
        StatusDot(health: .healthy, worstUsedPercent: 80, size: 14),
        size: size,
        region: region
    ) > 0.01)
    #expect(renderedDifferenceRatio(
        StatusDot(health: .healthy, worstUsedPercent: 20, size: 14),
        StatusDot(health: .error, worstUsedPercent: 20, size: 14),
        size: size,
        region: region
    ) > 0.01)
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
            FocusWidgetView(
                presentation: renderingPresentation(family: family),
                nowEpoch: 1_799_900_000
            ),
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

@MainActor
private func renderedDifferenceRatio<First: View, Second: View>(
    _ first: First,
    _ second: Second,
    size: CGSize,
    region: CGRect
) -> Double {
    guard let firstBitmap = renderedBitmap(first, size: size),
          let secondBitmap = renderedBitmap(second, size: size) else { return 0 }
    let minimumX = max(0, Int(region.minX.rounded(.down)))
    let maximumX = min(firstBitmap.pixelsWide, Int(region.maxX.rounded(.up)))
    let minimumY = max(0, Int(region.minY.rounded(.down)))
    let maximumY = min(firstBitmap.pixelsHigh, Int(region.maxY.rounded(.up)))
    var compared = 0
    var different = 0

    for y in minimumY..<maximumY {
        for x in minimumX..<maximumX {
            guard let firstColor = firstBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                  let secondColor = secondBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                continue
            }
            compared += 1
            let delta = abs(firstColor.redComponent - secondColor.redComponent)
                + abs(firstColor.greenComponent - secondColor.greenComponent)
                + abs(firstColor.blueComponent - secondColor.blueComponent)
                + abs(firstColor.alphaComponent - secondColor.alphaComponent)
            if delta > 0.08 { different += 1 }
        }
    }
    return Double(different) / Double(max(compared, 1))
}

@MainActor
private func renderedBitmap<V: View>(_ view: V, size: CGSize) -> NSBitmapImageRep? {
    let renderer = ImageRenderer(
        content: view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, ColorScheme.dark)
    )
    renderer.proposedSize = ProposedViewSize(size)
    renderer.scale = 1
    guard let data = renderer.nsImage?.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: data)
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
