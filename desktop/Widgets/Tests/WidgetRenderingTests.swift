import AgentMeterCore
import AgentMeterWidgetCore
import AppKit
import SwiftUI
import Testing

private let approvedWidgetSizes: [(AgentMeterWidgetCore.WidgetFamily, CGSize)] = [
    (.small, CGSize(width: 170, height: 170)),
    (.medium, CGSize(width: 360, height: 170)),
    (.large, CGSize(width: 360, height: 380)),
    (.extraLarge, CGSize(width: 720, height: 380)),
]

@MainActor
@Test(arguments: approvedWidgetSizes)
func dashboardAndFocusHaveSubstantiveRenderingAtEveryFamily(
    family: AgentMeterWidgetCore.WidgetFamily,
    size: CGSize
) {
    let dashboardIntent = configuredDashboardIntent()
    let focusIntent = configuredFocusIntent()

    for scheme in [ColorScheme.light, .dark] {
        assertSubstantiveRender(
            DashboardWidgetView(
                presentation: FictionalDashboardPresentationSource.presentation(
                    for: dashboardIntent,
                    family: family
                )
            ),
            size: size,
            colorScheme: scheme
        )
        assertSubstantiveRender(
            FocusWidgetView(
                presentation: FictionalFocusPresentationSource.presentation(
                    for: focusIntent,
                    family: family
                )
            ),
            size: size,
            colorScheme: scheme
        )
    }
}

@MainActor
@Test(arguments: [ColorScheme.light, .dark])
func dashboardUnavailableHistoryStateHasSubstantiveRendering(colorScheme: ColorScheme) {
    let intent = configuredDashboardIntent()
    intent.historyStyle = .trend
    intent.trendWindow = .focus
    let presentation = FictionalDashboardPresentationSource.presentation(for: intent, family: .large)

    #expect(presentation.history?.availabilityMessage == "History unavailable for this window")
    assertSubstantiveRender(
        DashboardWidgetView(presentation: presentation),
        size: CGSize(width: 360, height: 380),
        colorScheme: colorScheme
    )
}

@Test(arguments: [
    (AgentMeterWidgetCore.WidgetFamily.small, 2, 6, false),
    (.medium, 4, 4, false),
    (.large, 5, 3, true),
    (.extraLarge, 8, 0, true),
])
func dashboardFamilySemanticsExposeProviderCapacityOverflowAndHistory(
    family: AgentMeterWidgetCore.WidgetFamily,
    providerCount: Int,
    overflowCount: Int,
    showsHistory: Bool
) {
    let presentation = FictionalDashboardPresentationSource.presentation(
        for: configuredDashboardIntent(),
        family: family
    )
    let semantics = DashboardWidgetSemantics(presentation: presentation)

    #expect(semantics.visibleProviderCount == providerCount)
    #expect(semantics.overflowLabel == (overflowCount == 0 ? nil : "+\(overflowCount)"))
    #expect(semantics.showsHistory == showsHistory)
}

@Test func dashboardHistorySemanticsDescribeTruthfulScopeStyleAndRange() {
    let heatIntent = configuredDashboardIntent()
    heatIntent.historyStyle = .heatMap
    heatIntent.historyRange = .days30
    heatIntent.heatScope = .combined
    let heat = FictionalDashboardPresentationSource.presentation(for: heatIntent, family: .large)

    #expect(DashboardHistorySemantics(presentation: heat).title == "Average allowance consumed")
    #expect(DashboardHistorySemantics(presentation: heat).rangeLabel == "Last 30 days")
    #expect(DashboardHistorySemantics(presentation: heat).style == .heatMap)

    let trendIntent = configuredDashboardIntent()
    trendIntent.providers = [ProviderEntity(id: "gemini", name: "Gemini")]
    trendIntent.historyStyle = .trend
    trendIntent.historyRange = .days7
    trendIntent.trendWindow = .inner
    let trend = FictionalDashboardPresentationSource.presentation(for: trendIntent, family: .extraLarge)
    let trendSemantics = DashboardHistorySemantics(presentation: trend)

    #expect(trendSemantics.title == "Daily allowance used")
    #expect(trendSemantics.rangeLabel == "Last 7 days")
    #expect(trendSemantics.style == .trend)
    #expect(trend.history?.trendPoints.count == 7)
    #expect(trend.history?.trendPoints.contains(where: { $0.latestUsedPercent == nil }) == true)
}

@Test func dashboardRowsPreserveExactUnavailableCopyAndFullAccessibleNames() {
    let intent = configuredDashboardIntent()
    let presentation = FictionalDashboardPresentationSource.presentation(for: intent, family: .extraLarge)
    let longName = presentation.providers.first { $0.id == "longname" }
    let unknown = presentation.providers.first { $0.id == "claude" }?.rings.first
    let pending = presentation.providers.first { $0.id == "cursor" }?.rings.first

    #expect(longName?.name == "Aperture Research Allowance Service")
    #expect(longName.map(DashboardProviderAccessibility.summary)?.contains("Aperture Research Allowance Service") == true)
    #expect(unknown.map(DashboardProviderCopy.percentage) == "Not reported")
    #expect(unknown.map(DashboardProviderCopy.reset) == "Reset time unavailable")
    #expect(pending.map(DashboardProviderCopy.reset) == "Refresh pending")
}

@Test func extraLargeRowsExposeAdditionalWindowsWithoutInventingThemElsewhere() {
    let intent = configuredDashboardIntent()
    let large = FictionalDashboardPresentationSource.presentation(for: intent, family: .large)
    let extraLarge = FictionalDashboardPresentationSource.presentation(for: intent, family: .extraLarge)

    #expect(DashboardWidgetSemantics(presentation: large).additionalWindowLimit == 0)
    #expect(DashboardWidgetSemantics(presentation: extraLarge).additionalWindowLimit == 2)
    #expect(extraLarge.providers.first?.additionalWindows.isEmpty == false)
}

@Test func dashboardDestinationHonorsConfiguredRoutesAndFailsClosedForProvider() {
    let intent = configuredDashboardIntent()
    var presentation = FictionalDashboardPresentationSource.presentation(for: intent, family: .large)
    #expect(DashboardWidgetDestination.url(for: presentation) == AgentMeterRoute.overview.url)

    intent.tapDestination = .agents
    presentation = FictionalDashboardPresentationSource.presentation(for: intent, family: .large)
    #expect(DashboardWidgetDestination.url(for: presentation) == AgentMeterRoute.agents.url)

    intent.tapDestination = .providerDetail
    presentation = FictionalDashboardPresentationSource.presentation(for: intent, family: .large)
    #expect(DashboardWidgetDestination.url(for: presentation) == AgentMeterRoute.provider("codex").url)

    intent.providers = [ProviderEntity(id: "not valid", name: "Unknown")]
    presentation = FictionalDashboardPresentationSource.presentation(for: intent, family: .large)
    #expect(DashboardWidgetDestination.url(for: presentation) == AgentMeterRoute.overview.url)
}

@Test func fictionalDashboardSourceCarriesEveryIntentChoiceAndSelectedOrder() {
    let intent = DashboardWidgetIntent()
    intent.providers = [
        ProviderEntity(id: "gemini", name: "Gemini"),
        ProviderEntity(id: "missing", name: "Missing"),
        ProviderEntity(id: "codex", name: "Codex"),
    ]
    intent.percentage = .remaining
    intent.historyStyle = .trend
    intent.historyRange = .days7
    intent.heatScope = .singleProvider
    intent.trendWindow = .inner
    intent.layout = .compact
    intent.density = .compact
    intent.theme = .midnight
    intent.tapDestination = .agents
    intent.showResetCountdown = false
    intent.showAbsoluteResetDate = true
    intent.showStatus = true
    intent.showFreshness = true

    let presentation = FictionalDashboardPresentationSource.presentation(for: intent, family: .extraLarge)

    #expect(presentation.providers.map(\.id) == ["gemini", "codex"])
    #expect(presentation.providers.map { $0.rings.map(\.displayedPercent) } == [[37, 79], [58, 82]])
    #expect(presentation.configuration.percentageMode == .remaining)
    #expect(presentation.configuration.historyStyle == .trend)
    #expect(presentation.configuration.historyPeriod == .days7)
    #expect(presentation.configuration.heatMapScope == .singleProvider)
    #expect(presentation.configuration.trendWindow == .inner)
    #expect(presentation.configuration.layout == .compact)
    #expect(presentation.configuration.density == .compact)
    #expect(presentation.configuration.theme == .midnight)
    #expect(presentation.configuration.tapDestination == .agents)
    #expect(presentation.configuration.showsResetCountdown == false)
    #expect(presentation.configuration.showsAbsoluteResetDate)
    #expect(presentation.modules.contains(.status))
    #expect(presentation.modules.contains(.freshness))
    #expect(presentation.history?.windowLabel == "Daily")
    #expect(presentation.history?.trendPoints.count == 7)
}

@Test func dashboardViewSourceDoesNotIntroduceScrolling() throws {
    let dashboardDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Dashboard")
    for file in ["DashboardWidgetView.swift", "DashboardProviderRow.swift", "DashboardHistoryPanel.swift"] {
        let source = try String(contentsOf: dashboardDirectory.appendingPathComponent(file), encoding: .utf8)
        #expect(source.contains("ScrollView") == false)
    }
}

private func configuredDashboardIntent() -> DashboardWidgetIntent {
    let intent = DashboardWidgetIntent()
    intent.providers = FictionalDashboardPresentationSource.providerEntities
    intent.historyStyle = .heatMap
    intent.historyRange = .days30
    intent.heatScope = .combined
    intent.layout = .expanded
    intent.density = .compact
    intent.theme = .providerTinted
    intent.showResetCountdown = true
    intent.showAbsoluteResetDate = true
    intent.showStatus = true
    intent.showFreshness = true
    return intent
}

private func configuredFocusIntent() -> FocusWidgetIntent {
    let intent = FocusWidgetIntent()
    intent.provider = ProviderEntity(id: "claude", name: "Claude")
    intent.outerWindow = WindowEntity(providerID: "claude", windowKind: "monthly", label: "Monthly")
    intent.innerWindow = WindowEntity(providerID: "claude", windowKind: "session", label: "Session")
    intent.historyStyle = .trend
    intent.historyRange = .days7
    intent.theme = .midnight
    intent.showStatus = true
    intent.showFreshness = true
    return intent
}

@MainActor
private func assertSubstantiveRender<V: View>(
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
    guard let image,
          let data = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: data) else { return }

    let sampleStride = max(1, min(bitmap.pixelsWide, bitmap.pixelsHigh) / 100)
    var sampleCount = 0
    var nontransparentCount = 0
    var colors = Set<UInt32>()
    for y in Swift.stride(from: 0, to: bitmap.pixelsHigh, by: sampleStride) {
        for x in Swift.stride(from: 0, to: bitmap.pixelsWide, by: sampleStride) {
            sampleCount += 1
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                  color.alphaComponent >= 0.05 else { continue }
            nontransparentCount += 1
            let red = UInt32((color.redComponent * 15).rounded())
            let green = UInt32((color.greenComponent * 15).rounded())
            let blue = UInt32((color.blueComponent * 15).rounded())
            colors.insert((red << 8) | (green << 4) | blue)
        }
    }

    #expect(Double(nontransparentCount) / Double(max(sampleCount, 1)) >= 0.05)
    #expect(colors.count >= 6)
}
