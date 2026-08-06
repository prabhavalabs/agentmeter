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

@Test func dashboardLayoutPresetsProduceDistinctHistoryCapableStructures() {
    let automatic = dashboardLayoutPlan(.automatic, family: .large)
    let usageAndRings = dashboardLayoutPlan(.usageAndRings, family: .large)
    let compact = dashboardLayoutPlan(.compact, family: .large)
    let expanded = dashboardLayoutPlan(.expanded, family: .large)

    #expect(automatic.rowStyle == .detailed)
    #expect(automatic.providerColumns == 2)
    #expect(automatic.historyEmphasis == .balanced)

    #expect(usageAndRings.rowStyle == .dualCompact)
    #expect(usageAndRings.providerColumns == 2)
    #expect(usageAndRings.historyEmphasis == .compact)

    #expect(compact.rowStyle == .outerOnly)
    #expect(compact.providerColumns == 2)
    #expect(compact.historyEmphasis == .balanced)
    #expect(compact.spacing < automatic.spacing)

    #expect(expanded.rowStyle == .analyticsCompact)
    #expect(expanded.providerColumns == 1)
    #expect(expanded.historyEmphasis == .expanded)

    #expect(Set([automatic, usageAndRings, compact, expanded]).count == 4)
}

@Test func expandedAndCompactPresetsFallBackWithinCompactFamilyCapabilities() {
    let smallExpanded = dashboardLayoutPlan(.expanded, family: .small)
    let mediumExpanded = dashboardLayoutPlan(.expanded, family: .medium)
    let mediumCompact = dashboardLayoutPlan(.compact, family: .medium)

    #expect(smallExpanded.rowStyle == .outerOnly)
    #expect(smallExpanded.historyEmphasis == .hidden)
    #expect(mediumExpanded.rowStyle == .dualCompact)
    #expect(mediumExpanded.historyEmphasis == .hidden)
    #expect(mediumCompact.rowStyle == .outerOnly)
    #expect(mediumCompact.historyEmphasis == .hidden)
}

@MainActor
@Test(arguments: IntentLayoutOption.allCases)
func everyDashboardLayoutPresetHasSubstantiveLargeRendering(layout: IntentLayoutOption) {
    let presentation = presentationForLayout(layout, family: .large)
    for scheme in [ColorScheme.light, .dark] {
        assertSubstantiveRender(
            DashboardWidgetView(presentation: presentation),
            size: CGSize(width: 360, height: 380),
            colorScheme: scheme
        )
    }
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

    let singleHeatIntent = configuredDashboardIntent()
    singleHeatIntent.providers = [ProviderEntity(id: "codex", name: "Codex")]
    singleHeatIntent.historyStyle = .heatMap
    singleHeatIntent.heatScope = .singleProvider
    let singleHeat = FictionalDashboardPresentationSource.presentation(
        for: singleHeatIntent,
        family: .large
    )

    #expect(DashboardHistorySemantics(presentation: singleHeat).title == "Codex allowance consumed")
    #expect(DashboardHistorySemantics(presentation: singleHeat).title != "Average allowance consumed")

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
    #expect(longName.map {
        DashboardProviderAccessibility.summary(
            $0,
            percentageMode: .used,
            style: .expanded,
            additionalWindowLimit: 2,
            modules: presentation.modules,
            freshness: presentation.freshness,
            showsMetadata: true,
            showsResetCountdown: true,
            showsAbsoluteResetDate: true,
            relativeTo: Date(timeIntervalSince1970: 1_799_996_400)
        )
    }?.contains("Aperture Research Allowance Service") == true)
    #expect(unknown.map(DashboardProviderCopy.percentage) == "Not reported")
    #expect(unknown.map(DashboardProviderCopy.reset) == "Reset time unavailable")
    #expect(pending.map(DashboardProviderCopy.reset) == "Refresh pending")
}

@Test func scheduledResetOptionsRemainIndependent() {
    let ring = WidgetRingPresentation(
        windowKind: "monthly",
        label: "Monthly",
        usedPercent: 42,
        displayedPercent: 42,
        resetState: .scheduled(epoch: 1_800_000_000)
    )
    let referenceDate = Date(timeIntervalSince1970: 1_799_996_400)

    let neither = DashboardResetPresentation(
        ring: ring,
        showsCountdown: false,
        showsAbsoluteDate: false,
        relativeTo: referenceDate
    )
    let countdown = DashboardResetPresentation(
        ring: ring,
        showsCountdown: true,
        showsAbsoluteDate: false,
        relativeTo: referenceDate
    )
    let absolute = DashboardResetPresentation(
        ring: ring,
        showsCountdown: false,
        showsAbsoluteDate: true,
        relativeTo: referenceDate
    )
    let both = DashboardResetPresentation(
        ring: ring,
        showsCountdown: true,
        showsAbsoluteDate: true,
        relativeTo: referenceDate
    )

    #expect(neither.lines == ["Reset scheduled"])
    #expect(countdown.lines.count == 1)
    #expect(countdown.lines.first?.hasPrefix("Reset countdown ") == true)
    #expect(absolute.lines.count == 1)
    #expect(absolute.lines.first?.hasPrefix("Reset date ") == true)
    #expect(both.lines.count == 2)
    #expect(both.lines.contains(where: { $0.hasPrefix("Reset countdown ") }))
    #expect(both.lines.contains(where: { $0.hasPrefix("Reset date ") }))
}

@Test func pendingAndUnavailableResetCopyRemainExactForEveryToggleCombination() {
    let referenceDate = Date(timeIntervalSince1970: 1_799_996_400)
    let pending = WidgetRingPresentation(
        windowKind: "weekly",
        label: "Weekly",
        usedPercent: 10,
        displayedPercent: 10,
        resetState: .pending
    )
    let unavailable = WidgetRingPresentation(
        windowKind: "session",
        label: "Session",
        usedPercent: nil,
        displayedPercent: nil,
        resetState: .unavailable
    )

    for showsCountdown in [false, true] {
        for showsAbsoluteDate in [false, true] {
            #expect(DashboardResetPresentation(
                ring: pending,
                showsCountdown: showsCountdown,
                showsAbsoluteDate: showsAbsoluteDate,
                relativeTo: referenceDate
            ).lines == ["Refresh pending"])
            #expect(DashboardResetPresentation(
                ring: unavailable,
                showsCountdown: showsCountdown,
                showsAbsoluteDate: showsAbsoluteDate,
                relativeTo: referenceDate
            ).lines == ["Reset time unavailable"])
        }
    }
}

@Test func expandedProviderAccessibilityDescribesEveryVisibleStateAndOption() {
    let provider = WidgetProviderPresentation(
        id: "longname",
        name: "Aperture Research Allowance Service",
        status: "Action required",
        rings: [
            WidgetRingPresentation(
                windowKind: "monthly",
                label: "Monthly allowance",
                usedPercent: 42,
                displayedPercent: 58,
                resetState: .scheduled(epoch: 1_800_000_000)
            ),
            WidgetRingPresentation(
                windowKind: "session",
                label: "Session allowance",
                usedPercent: nil,
                displayedPercent: nil,
                resetState: .unavailable
            ),
        ],
        additionalWindows: [
            WidgetRingPresentation(
                windowKind: "weekly",
                label: "Weekly allowance",
                usedPercent: 27,
                displayedPercent: 73,
                resetState: .pending
            ),
        ]
    )

    let summary = DashboardProviderAccessibility.summary(
        provider,
        percentageMode: .remaining,
        style: .expanded,
        additionalWindowLimit: 2,
        modules: [.status, .freshness],
        freshness: .stale,
        showsMetadata: true,
        showsResetCountdown: true,
        showsAbsoluteResetDate: true,
        relativeTo: Date(timeIntervalSince1970: 1_799_996_400)
    )

    #expect(summary.contains("Aperture Research Allowance Service"))
    #expect(summary.contains("Monthly allowance, 58 percent remaining"))
    #expect(summary.contains("Reset countdown "))
    #expect(summary.contains("Reset date "))
    #expect(summary.contains("Session allowance, Not reported, Reset time unavailable"))
    #expect(summary.contains("Weekly allowance, 73 percent remaining, Refresh pending"))
    #expect(summary.contains("Status Action required"))
    #expect(summary.contains("Freshness Stale"))
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

@Test func dashboardIntentAdapterCoversEveryLayoutDensityThemeAndPercentageChoice() {
    let layoutCases: [(IntentLayoutOption, WidgetLayoutPreset)] = [
        (.automatic, .automatic),
        (.usageAndRings, .usageAndRings),
        (.compact, .compact),
        (.expanded, .expanded),
    ]
    for (choice, expected) in layoutCases {
        let intent = DashboardWidgetIntent()
        intent.layout = choice
        #expect(IntentConfigurationAdapter.dashboard(intent).layout == expected)
    }

    let densityCases: [(IntentDensityOption, WidgetDensity)] = [
        (.compact, .compact),
        (.comfortable, .comfortable),
    ]
    for (choice, expected) in densityCases {
        let intent = DashboardWidgetIntent()
        intent.density = choice
        #expect(IntentConfigurationAdapter.dashboard(intent).density == expected)
    }

    let themeCases: [(IntentThemeOption, WidgetTheme)] = [
        (.system, .system),
        (.light, .light),
        (.dark, .dark),
        (.midnight, .midnight),
        (.neutral, .neutral),
        (.providerTinted, .providerTinted),
    ]
    for (choice, expected) in themeCases {
        let intent = DashboardWidgetIntent()
        intent.theme = choice
        #expect(IntentConfigurationAdapter.dashboard(intent).theme == expected)
    }

    let percentageCases: [(IntentPercentageOption, WidgetPercentageMode)] = [
        (.used, .used),
        (.remaining, .remaining),
    ]
    for (choice, expected) in percentageCases {
        let intent = DashboardWidgetIntent()
        intent.percentage = choice
        #expect(IntentConfigurationAdapter.dashboard(intent).percentageMode == expected)
    }
}

@Test func dashboardIntentAdapterCoversEveryResetToggleCombination() {
    for showsCountdown in [false, true] {
        for showsAbsoluteDate in [false, true] {
            let intent = DashboardWidgetIntent()
            intent.showResetCountdown = showsCountdown
            intent.showAbsoluteResetDate = showsAbsoluteDate
            let configuration = IntentConfigurationAdapter.dashboard(intent)

            #expect(configuration.showsResetCountdown == showsCountdown)
            #expect(configuration.showsAbsoluteResetDate == showsAbsoluteDate)
        }
    }
}

@MainActor
@Test func practicalDashboardIntentScenariosResolveAndRenderEndToEnd() {
    let scenarios: [DashboardEndToEndScenario] = [
        DashboardEndToEndScenario(
            layout: .automatic,
            expectedLayout: .automatic,
            density: .comfortable,
            expectedDensity: .comfortable,
            theme: .system,
            expectedTheme: .system,
            percentage: .used,
            expectedPercentage: .used,
            historyStyle: .heatMap,
            expectedHistoryStyle: .heatMap,
            historyRange: .days30,
            expectedHistoryPeriod: .days30,
            heatScope: .combined,
            expectedHeatScope: .combined,
            trendWindow: .outer,
            expectedTrendWindow: .outer,
            showsCountdown: true,
            showsAbsoluteDate: false,
            showsStatus: false,
            showsFreshness: true,
            tapDestination: .overview,
            expectedTapDestination: .overview,
            expectedModules: [.usage, .primaryReset, .history, .freshness],
            expectedHistoryWindowLabel: nil,
            expectedURL: AgentMeterRoute.overview.url
        ),
        DashboardEndToEndScenario(
            layout: .usageAndRings,
            expectedLayout: .usageAndRings,
            density: .comfortable,
            expectedDensity: .comfortable,
            theme: .providerTinted,
            expectedTheme: .providerTinted,
            percentage: .remaining,
            expectedPercentage: .remaining,
            historyStyle: .heatMap,
            expectedHistoryStyle: .heatMap,
            historyRange: .days7,
            expectedHistoryPeriod: .days7,
            heatScope: .singleProvider,
            expectedHeatScope: .singleProvider,
            trendWindow: .outer,
            expectedTrendWindow: .outer,
            showsCountdown: false,
            showsAbsoluteDate: true,
            showsStatus: true,
            showsFreshness: false,
            tapDestination: .agents,
            expectedTapDestination: .agents,
            expectedModules: [.usage, .primaryReset, .history, .status],
            expectedHistoryWindowLabel: nil,
            expectedURL: AgentMeterRoute.agents.url
        ),
        DashboardEndToEndScenario(
            layout: .compact,
            expectedLayout: .compact,
            density: .compact,
            expectedDensity: .compact,
            theme: .neutral,
            expectedTheme: .neutral,
            percentage: .used,
            expectedPercentage: .used,
            historyStyle: .none,
            expectedHistoryStyle: .none,
            historyRange: .days30,
            expectedHistoryPeriod: .days30,
            heatScope: .combined,
            expectedHeatScope: .combined,
            trendWindow: .outer,
            expectedTrendWindow: .outer,
            showsCountdown: false,
            showsAbsoluteDate: false,
            showsStatus: false,
            showsFreshness: true,
            tapDestination: .providerDetail,
            expectedTapDestination: .providerDetail,
            expectedModules: [.usage, .primaryReset, .freshness],
            expectedHistoryWindowLabel: nil,
            expectedURL: AgentMeterRoute.provider("gemini").url
        ),
        DashboardEndToEndScenario(
            layout: .expanded,
            expectedLayout: .expanded,
            density: .compact,
            expectedDensity: .compact,
            theme: .midnight,
            expectedTheme: .midnight,
            percentage: .remaining,
            expectedPercentage: .remaining,
            historyStyle: .trend,
            expectedHistoryStyle: .trend,
            historyRange: .days7,
            expectedHistoryPeriod: .days7,
            heatScope: .singleProvider,
            expectedHeatScope: .singleProvider,
            trendWindow: .inner,
            expectedTrendWindow: .inner,
            showsCountdown: true,
            showsAbsoluteDate: true,
            showsStatus: true,
            showsFreshness: true,
            tapDestination: .agents,
            expectedTapDestination: .agents,
            expectedModules: [.usage, .primaryReset, .history, .status, .freshness],
            expectedHistoryWindowLabel: "Daily",
            expectedURL: AgentMeterRoute.agents.url
        ),
    ]
    let selectedProviders = [
        ProviderEntity(id: "gemini", name: "Gemini"),
        ProviderEntity(id: "claude", name: "Claude"),
        ProviderEntity(id: "codex", name: "Codex"),
        ProviderEntity(id: "cursor", name: "Cursor"),
        ProviderEntity(id: "longname", name: "Aperture Research Allowance Service"),
        ProviderEntity(id: "atlas", name: "Atlas"),
        ProviderEntity(id: "nova", name: "Nova"),
        ProviderEntity(id: "prism", name: "Prism"),
    ]
    let expectedVisibleProviderIDs = ["gemini", "claude", "codex", "cursor", "longname"]

    for scenario in scenarios {
        let intent = DashboardWidgetIntent()
        intent.providers = selectedProviders
        intent.layout = scenario.layout
        intent.density = scenario.density
        intent.theme = scenario.theme
        intent.percentage = scenario.percentage
        intent.historyStyle = scenario.historyStyle
        intent.historyRange = scenario.historyRange
        intent.heatScope = scenario.heatScope
        intent.trendWindow = scenario.trendWindow
        intent.showResetCountdown = scenario.showsCountdown
        intent.showAbsoluteResetDate = scenario.showsAbsoluteDate
        intent.showStatus = scenario.showsStatus
        intent.showFreshness = scenario.showsFreshness
        intent.tapDestination = scenario.tapDestination

        let presentation = FictionalDashboardPresentationSource.presentation(for: intent, family: .large)
        let configuration = presentation.configuration
        let semantics = DashboardWidgetSemantics(presentation: presentation)

        #expect(configuration.kind == .dashboard)
        #expect(presentation.family == .large)
        #expect(configuration.layout == scenario.expectedLayout)
        #expect(configuration.density == scenario.expectedDensity)
        #expect(configuration.theme == scenario.expectedTheme)
        #expect(configuration.percentageMode == scenario.expectedPercentage)
        #expect(configuration.historyStyle == scenario.expectedHistoryStyle)
        #expect(configuration.historyPeriod == scenario.expectedHistoryPeriod)
        #expect(configuration.heatMapScope == scenario.expectedHeatScope)
        #expect(configuration.trendWindow == scenario.expectedTrendWindow)
        #expect(configuration.showsResetCountdown == scenario.showsCountdown)
        #expect(configuration.showsAbsoluteResetDate == scenario.showsAbsoluteDate)
        #expect(configuration.tapDestination == scenario.expectedTapDestination)
        #expect(presentation.modules == scenario.expectedModules)
        #expect(presentation.providers.map(\.id) == expectedVisibleProviderIDs)
        #expect(semantics.visibleProviderCount == 5)
        #expect(presentation.overflowCount == 3)
        #expect(semantics.overflowLabel == "+3")
        #expect(semantics.showsHistory == (scenario.expectedHistoryStyle != .none))
        #expect(DashboardWidgetDestination.url(for: presentation) == scenario.expectedURL)
        if let expectedHistoryWindowLabel = scenario.expectedHistoryWindowLabel {
            #expect(presentation.history?.windowLabel == expectedHistoryWindowLabel)
        } else if scenario.expectedHistoryStyle == .none {
            #expect(presentation.history == nil)
        } else {
            #expect(presentation.history != nil)
        }

        let colorSchemes: [ColorScheme] = scenario.expectedTheme == .midnight
            ? [.dark]
            : [.light, .dark]
        for colorScheme in colorSchemes {
            assertSubstantiveRender(
                DashboardWidgetView(presentation: presentation),
                size: CGSize(width: 360, height: 380),
                colorScheme: colorScheme
            )
        }
    }
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

private func dashboardLayoutPlan(
    _ layout: IntentLayoutOption,
    family: AgentMeterWidgetCore.WidgetFamily
) -> DashboardLayoutPlan {
    DashboardLayoutPlan(presentation: presentationForLayout(layout, family: family))
}

private func presentationForLayout(
    _ layout: IntentLayoutOption,
    family: AgentMeterWidgetCore.WidgetFamily
) -> WidgetPresentation {
    let intent = configuredDashboardIntent()
    intent.layout = layout
    return FictionalDashboardPresentationSource.presentation(for: intent, family: family)
}

private struct DashboardEndToEndScenario {
    let layout: IntentLayoutOption
    let expectedLayout: WidgetLayoutPreset
    let density: IntentDensityOption
    let expectedDensity: WidgetDensity
    let theme: IntentThemeOption
    let expectedTheme: WidgetTheme
    let percentage: IntentPercentageOption
    let expectedPercentage: WidgetPercentageMode
    let historyStyle: IntentHistoryStyleOption
    let expectedHistoryStyle: WidgetHistoryStyle
    let historyRange: IntentHistoryRangeOption
    let expectedHistoryPeriod: WidgetHistoryPeriod
    let heatScope: IntentHeatScopeOption
    let expectedHeatScope: WidgetHeatMapScope
    let trendWindow: IntentTrendWindowOption
    let expectedTrendWindow: WidgetTrendWindow
    let showsCountdown: Bool
    let showsAbsoluteDate: Bool
    let showsStatus: Bool
    let showsFreshness: Bool
    let tapDestination: IntentTapDestinationOption
    let expectedTapDestination: WidgetTapDestination
    let expectedModules: Set<WidgetModule>
    let expectedHistoryWindowLabel: String?
    let expectedURL: URL
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
