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
@Test(arguments: WidgetTimelineViewState.allCases)
func everyTimelineFailureStateHasSubstantiveAccessibleRendering(state: WidgetTimelineViewState) {
    assertSubstantiveRender(
        WidgetTimelineStateView(state: state),
        size: CGSize(width: 170, height: 170),
        colorScheme: .dark
    )
    #expect(state.message.isEmpty == false)
    #expect(state.accessibilityLabel.isEmpty == false)
}

@MainActor
@Test func dashboardProviderRowComposesLiveResetCountdownAndExactPendingCopy() throws {
    let presentation = FictionalDashboardPresentationSource.presentation(
        for: configuredDashboardIntent(),
        family: .small
    )
    let provider = try #require(presentation.providers.first)
    let nowEpoch = FictionalDashboardPresentationSource.nowEpoch
    let soon = WidgetRingPresentation(
        windowKind: "session",
        label: "Session",
        usedPercent: 18,
        displayedPercent: 18,
        resetState: .scheduled(epoch: nowEpoch + 4_000)
    )
    let pending = WidgetRingPresentation(
        windowKind: "weekly",
        label: "Weekly",
        usedPercent: 42,
        displayedPercent: 42,
        resetState: .pending
    )

    #expect(ResetSummarySemantics(
        presentation: soon,
        showsCountdown: true,
        showsAbsoluteDate: false,
        nowEpoch: nowEpoch
    ).content == [
        .liveRelative(Date(timeIntervalSince1970: TimeInterval(nowEpoch + 4_000))),
    ])
    #expect(ResetSummarySemantics(
        presentation: pending,
        showsCountdown: true,
        showsAbsoluteDate: false,
        nowEpoch: nowEpoch
    ).content == [.text("Refresh pending")])
    assertSubstantiveRender(
        DashboardProviderRow(
            provider: provider,
            theme: presentation.configuration.theme,
            nowEpoch: nowEpoch
        ),
        size: CGSize(width: 340, height: 44),
        colorScheme: .dark
    )
}

@MainActor
@Test(arguments: [
    AgentMeterWidgetCore.WidgetFamily.medium,
    .large,
    .extraLarge,
])
func dashboardWidgetViewComposesRootDestinationAndDistinctProviderLinksOutsideSmall(
    family: AgentMeterWidgetCore.WidgetFamily
) {
    let presentation = FictionalDashboardPresentationSource.presentation(
        for: configuredDashboardIntent(),
        family: family
    )
    let view = DashboardWidgetView(presentation: presentation)
    let interactions = view.interactionComposition

    #expect(interactions.widgetURL == AgentMeterRoute.overview.url)
    #expect(interactions.providerURLs.count == presentation.providers.count)
    #expect(interactions.providerURLs.values.allSatisfy {
        if case .provider = AgentMeterRoute(url: $0) { return true }
        return false
    })
    #expect(Set(interactions.providerURLs.values).count == presentation.providers.count)
    #expect(dashboardBodyContainsLink(view))
}

@MainActor
@Test func smallDashboardWidgetViewComposesOneWidgetURLAndNoProviderLinks() {
    let presentation = FictionalDashboardPresentationSource.presentation(
        for: configuredDashboardIntent(),
        family: .small
    )
    let view = DashboardWidgetView(presentation: presentation)
    let interactions = view.interactionComposition

    #expect(interactions.widgetURL?.absoluteString == "agentmeter://overview")
    #expect(interactions.providerURLs.isEmpty)
    assertSubstantiveRender(
        view,
        size: CGSize(width: 170, height: 170),
        colorScheme: .dark
    )
}

@MainActor
@Test(arguments: [ColorScheme.light, .dark])
func legacyDashboardFocusTrendFallsBackToRenderedOuterHistory(colorScheme: ColorScheme) {
    let intent = configuredDashboardIntent()
    intent.historyStyle = .trend
    intent.trendWindow = .focus
    let presentation = FictionalDashboardPresentationSource.presentation(for: intent, family: .large)

    #expect(presentation.configuration.trendWindow == .outer)
    #expect(presentation.history?.availabilityMessage == nil)
    #expect(presentation.history?.windowLabel != nil)
    assertSubstantiveRender(
        DashboardWidgetView(presentation: presentation),
        size: CGSize(width: 360, height: 380),
        colorScheme: colorScheme
    )
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

    #expect(presentation.providers.count == providerCount)
    #expect(presentation.overflowCount == overflowCount)
    #expect((presentation.history != nil) == showsHistory)
}

@Test func dashboardHistoryProjectionsStayTruthfulAcrossScopeStyleAndRange() {
    let heatIntent = configuredDashboardIntent()
    heatIntent.historyStyle = .heatMap
    heatIntent.historyRange = .days30
    heatIntent.heatScope = .combined
    let heat = FictionalDashboardPresentationSource.presentation(for: heatIntent, family: .large)

    #expect(heat.configuration.historyStyle == .heatMap)
    #expect(heat.configuration.historyPeriod.displayLabel == "Last 30 days")
    #expect(heat.history?.availabilityMessage == nil)
    #expect(heat.history?.cells.count == 30)

    let singleHeatIntent = configuredDashboardIntent()
    singleHeatIntent.providers = [ProviderEntity(id: "codex", name: "Codex")]
    singleHeatIntent.historyStyle = .heatMap
    singleHeatIntent.heatScope = .singleProvider
    let singleHeat = FictionalDashboardPresentationSource.presentation(
        for: singleHeatIntent,
        family: .large
    )

    #expect(singleHeat.history?.cells.isEmpty == false)
    #expect(singleHeat.history?.cells.contains(where: { $0.hasData == false }) == true)

    let trendIntent = configuredDashboardIntent()
    trendIntent.providers = [ProviderEntity(id: "gemini", name: "Gemini")]
    trendIntent.historyStyle = .trend
    trendIntent.historyRange = .days7
    trendIntent.trendWindow = .inner
    let trend = FictionalDashboardPresentationSource.presentation(for: trendIntent, family: .extraLarge)

    #expect(trend.configuration.historyStyle == .trend)
    #expect(trend.configuration.historyPeriod.displayLabel == "Last 7 days")
    #expect(trend.history?.windowLabel == "Daily")
    #expect(trend.history?.trendPoints.count == 7)
    #expect(trend.history?.trendPoints.contains(where: { $0.latestUsedPercent == nil }) == true)
}

@MainActor
@Test func dashboardRowsPreserveExactUnavailableCopyAndLongNames() throws {
    let intent = configuredDashboardIntent()
    let presentation = FictionalDashboardPresentationSource.presentation(for: intent, family: .extraLarge)
    let longName = presentation.providers.first { $0.id == "longname" }
    let unknown = presentation.providers.first { $0.id == "claude" }?.rings.first
    let pending = presentation.providers.first { $0.id == "cursor" }?.rings.first
    let nowEpoch = FictionalDashboardPresentationSource.nowEpoch

    #expect(longName?.name == "Aperture Research Allowance Service")
    #expect(unknown?.usedPercent == nil)
    #expect(unknown?.displayedPercent == nil)
    #expect(unknown?.resetState == .unavailable)
    #expect(WidgetResetPhrasing.longText(
        WidgetResetPhrasing.phrase(for: .unavailable, nowEpoch: nowEpoch),
        nowEpoch: nowEpoch
    ) == "Reset unavailable")
    #expect(WidgetResetPhrasing.compactText(
        WidgetResetPhrasing.phrase(for: .unavailable, nowEpoch: nowEpoch),
        nowEpoch: nowEpoch
    ) == "—")
    #expect(pending?.resetState == .pending)
    #expect(pending?.resetText == "Refresh pending")
    #expect(WidgetResetPhrasing.longText(.pending, nowEpoch: nowEpoch) == "Refresh pending")

    let row = DashboardProviderRow(
        provider: try #require(longName),
        theme: presentation.configuration.theme,
        nowEpoch: nowEpoch
    )
    assertSubstantiveRender(row, size: CGSize(width: 340, height: 44), colorScheme: .light)
}

/// A row whose hero window has no reported percent must render differently
/// from one at 0% — the nil truth may never collapse to zero.
@MainActor
@Test func dashboardRowRendersNilAndZeroPercentDistinctly() {
    let theme = WidgetTheme.midnight
    let nowEpoch = FictionalDashboardPresentationSource.nowEpoch
    let ring: (Int?) -> WidgetRingPresentation = { percent in
        WidgetRingPresentation(
            windowKind: "monthly",
            label: "Monthly",
            usedPercent: percent,
            displayedPercent: percent,
            resetState: percent == nil ? .unavailable : .scheduled(epoch: nowEpoch + 4_000)
        )
    }
    let provider: (Int?) -> WidgetProviderPresentation = { percent in
        WidgetProviderPresentation(
            id: "claude",
            name: "Claude",
            status: "ok",
            rings: [ring(percent)]
        )
    }
    let size = CGSize(width: 340, height: 44)

    #expect(renderedDifferenceRatio(
        DashboardProviderRow(provider: provider(nil), theme: theme, nowEpoch: nowEpoch),
        DashboardProviderRow(provider: provider(0), theme: theme, nowEpoch: nowEpoch),
        size: size,
        region: CGRect(origin: .zero, size: size)
    ) > 0.005)
}

@Test func scheduledResetSemanticsFollowDistanceClassesAndCountdownToggle() {
    let nowEpoch = 1_799_996_400
    let soonEpoch = nowEpoch + 3_600
    let weekEpoch = nowEpoch + 2 * 86_400
    let farEpoch = nowEpoch + 10 * 86_400
    let ring: (Int) -> WidgetRingPresentation = { epoch in
        WidgetRingPresentation(
            windowKind: "monthly",
            label: "Monthly",
            usedPercent: 42,
            displayedPercent: 42,
            resetState: .scheduled(epoch: epoch)
        )
    }

    // Under 24 hours: countdown toggle switches between the live-updating
    // rendering and the deterministic long text.
    #expect(ResetSummarySemantics(
        presentation: ring(soonEpoch),
        showsCountdown: true,
        showsAbsoluteDate: false,
        nowEpoch: nowEpoch
    ).content == [.liveRelative(Date(timeIntervalSince1970: TimeInterval(soonEpoch)))])
    let staticSoon = ResetSummarySemantics(
        presentation: ring(soonEpoch),
        showsCountdown: false,
        showsAbsoluteDate: false,
        nowEpoch: nowEpoch
    )
    #expect(staticSoon.content == [.text("Resets in 1 hr")])
    #expect(staticSoon.accessibilityLines(
        relativeTo: Date(timeIntervalSince1970: TimeInterval(nowEpoch))
    ) == ["Resets in 1 hr"])

    // Beyond 24 hours the copy is always static, regardless of the toggles.
    for showsCountdown in [false, true] {
        for showsAbsoluteDate in [false, true] {
            let week = ResetSummarySemantics(
                presentation: ring(weekEpoch),
                showsCountdown: showsCountdown,
                showsAbsoluteDate: showsAbsoluteDate,
                nowEpoch: nowEpoch
            )
            #expect(week.phrase == .weekdayTime(epoch: weekEpoch))
            #expect(week.content == [.text(
                WidgetResetPhrasing.longText(.weekdayTime(epoch: weekEpoch), nowEpoch: nowEpoch)
            )])

            let far = ResetSummarySemantics(
                presentation: ring(farEpoch),
                showsCountdown: showsCountdown,
                showsAbsoluteDate: showsAbsoluteDate,
                nowEpoch: nowEpoch
            )
            #expect(far.phrase == .calendarDate(epoch: farEpoch))
            #expect(far.content == [.text(
                WidgetResetPhrasing.longText(.calendarDate(epoch: farEpoch), nowEpoch: nowEpoch)
            )])
        }
    }

    // Exact phrasing-table strings, pinned in a deterministic zone and locale.
    let utc = TimeZone(secondsFromGMT: 0)!
    let posix = Locale(identifier: "en_US_POSIX")
    #expect(WidgetResetPhrasing.longText(
        .relative(epoch: soonEpoch),
        nowEpoch: nowEpoch,
        timeZone: utc,
        locale: posix
    ) == "Resets in 1 hr")
    #expect(WidgetResetPhrasing.longText(
        .weekdayTime(epoch: weekEpoch),
        nowEpoch: nowEpoch,
        timeZone: utc,
        locale: posix
    ) == "Resets Sun 7:00 AM")
    #expect(WidgetResetPhrasing.longText(
        .calendarDate(epoch: farEpoch),
        nowEpoch: nowEpoch,
        timeZone: utc,
        locale: posix
    ) == "Resets Mon 25 Jan")
}

@Test func pendingAndUnavailableResetCopyRemainExactForEveryToggleCombination() {
    let nowEpoch = 1_799_996_400
    let referenceDate = Date(timeIntervalSince1970: TimeInterval(nowEpoch))
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
            let pendingSemantics = ResetSummarySemantics(
                presentation: pending,
                showsCountdown: showsCountdown,
                showsAbsoluteDate: showsAbsoluteDate,
                nowEpoch: nowEpoch
            )
            #expect(pendingSemantics.content == [.text("Refresh pending")])
            #expect(pendingSemantics.accessibilityLines(relativeTo: referenceDate) == ["Refresh pending"])
            #expect(pendingSemantics.compactText == "⟳ …")

            let unavailableSemantics = ResetSummarySemantics(
                presentation: unavailable,
                showsCountdown: showsCountdown,
                showsAbsoluteDate: showsAbsoluteDate,
                nowEpoch: nowEpoch
            )
            #expect(unavailableSemantics.content == [.text("Reset unavailable")])
            #expect(unavailableSemantics.accessibilityLines(relativeTo: referenceDate) == ["Reset unavailable"])
            #expect(unavailableSemantics.compactText == "—")
        }
    }
}

/// Mixed known/unknown/pending windows must render as a real row, and every
/// reset state must resolve to its exact v2 phrasing.
@MainActor
@Test func providerRowWithMixedWindowStatesRendersAndKeepsExactResetPhrasing() {
    let nowEpoch = 1_799_996_400
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
                resetState: .scheduled(epoch: nowEpoch + 3_600)
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

    let states = provider.rings + provider.additionalWindows
    let phrases = states.map {
        WidgetResetPhrasing.longText(
            WidgetResetPhrasing.phrase(for: $0.resetState, nowEpoch: nowEpoch),
            nowEpoch: nowEpoch
        )
    }
    #expect(phrases == ["Resets in 1 hr", "Reset unavailable", "Refresh pending"])
    #expect(states.map(\.displayedPercent) == [58, nil, 73])
    assertSubstantiveRender(
        DashboardProviderRow(provider: provider, theme: .midnight, nowEpoch: nowEpoch),
        size: CGSize(width: 340, height: 44),
        colorScheme: .dark
    )
}

@Test func exceptionalHealthRemainsVisibleAndAccessibleWhenMetadataIsDisabled() {
    let provider = WidgetProviderPresentation(
        id: "codex",
        name: "Codex",
        status: "error at /private/path",
        healthState: .error,
        rings: [
            WidgetRingPresentation(
                windowKind: "weekly",
                label: "Weekly",
                usedPercent: 42,
                displayedPercent: 42,
                resetState: .scheduled(epoch: 1_800_000_000)
            ),
        ]
    )

    #expect(WidgetHealthSemantics.mandatoryLabels(
        provider: provider,
        freshness: .stale
    ) == ["Agent error", "Stale"])
    #expect(WidgetHealthSemantics.mandatoryLabels(
        provider: WidgetProviderPresentation(
            id: "codex",
            name: "Codex",
            status: "stale",
            healthState: .stale,
            rings: provider.rings
        ),
        freshness: .stale
    ) == ["Stale"])

    // The mandatory labels are the health copy both widgets surface — they
    // must expose the exceptional state without leaking raw status detail.
    let labels = WidgetHealthSemantics.mandatoryLabels(provider: provider, freshness: .stale)
    #expect(labels.contains("Agent error"))
    #expect(labels.contains("Stale"))
    #expect(labels.allSatisfy { $0.contains("/private/path") == false })
}

@MainActor
@Test(arguments: approvedWidgetSizes)
func exceptionalHealthRendersInDashboardAndFocusAtEveryFamily(
    family: AgentMeterWidgetCore.WidgetFamily,
    size: CGSize
) {
    let dashboard = exceptionalHealthPresentation(kind: .dashboard, family: family)
    let focus = exceptionalHealthPresentation(kind: .focus, family: family)

    assertSubstantiveRender(
        DashboardWidgetView(presentation: dashboard),
        size: size,
        colorScheme: .light
    )
    assertSubstantiveRender(
        FocusWidgetView(presentation: focus),
        size: size,
        colorScheme: .dark
    )
}

@MainActor
@Test func focusWithoutUsageStillRendersExceptionalProviderHealth() {
    let configuration = IntentConfigurationAdapter.focus(configuredFocusIntent())
    let provider = WidgetProviderPresentation(
        id: "codex",
        name: "Codex",
        status: "error",
        healthState: .error,
        rings: []
    )
    let presentation = WidgetPresentation(
        configuration: configuration,
        family: .small,
        providers: [provider],
        modules: [.usage, .primaryReset],
        history: nil,
        freshness: .stale,
        overflowCount: 0
    )

    #expect(WidgetHealthSemantics.mandatoryLabels(
        provider: provider,
        freshness: presentation.freshness
    ) == ["Agent error", "Stale"])
    assertSubstantiveRender(
        FocusWidgetView(presentation: presentation),
        size: CGSize(width: 170, height: 170),
        colorScheme: .dark
    )
}

@MainActor
@Test func compactHealthBadgesKeepEveryFullAccessibilityLabelInNarrowHeaders() {
    let badges = WidgetHealthBadges(labels: ["Agent error", "Stale"], compact: true)

    #expect(badges.accessibilitySummary == "Agent error, Stale")
    assertSubstantiveRender(
        badges,
        size: CGSize(width: 52, height: 24),
        colorScheme: .dark
    )
}

@Test func leadingDashboardTombstoneUsesFirstAvailableProviderForRoutesLinksAndHistory() {
    let intent = configuredDashboardIntent()
    intent.providers = [
        ProviderEntity(id: "private-account@example.com", name: "Private Account"),
        ProviderEntity(id: "codex", name: "Codex"),
    ]
    intent.tapDestination = .providerDetail
    intent.heatScope = .singleProvider
    let presentation = FictionalDashboardPresentationSource.presentation(for: intent, family: .large)
    let interactions = DashboardWidgetInteractions(presentation: presentation)

    #expect(presentation.providers.first?.name == "Agent unavailable")
    #expect(interactions.widgetURL == AgentMeterRoute.provider("codex").url)
    #expect(interactions.providerURLs == ["codex": AgentMeterRoute.provider("codex").url])
    #expect(interactions.providerURL(for: presentation.providers[0]) == nil)
    #expect(interactions.providerURL(for: presentation.providers[1]) == AgentMeterRoute.provider("codex").url)
    #expect(interactions.providerURL(for: WidgetProviderPresentation(
        id: "codex",
        name: "Agent unavailable",
        status: "Agent unavailable",
        availability: .missing,
        healthState: .unavailable,
        rings: []
    )) == nil)
    #expect(presentation.configuration.heatMapScope == .singleProvider)
    #expect(presentation.history?.cells.isEmpty == false)
}

@MainActor
@Test(arguments: approvedWidgetSizes)
func everyFocusLayoutPresetAndDensityRenders(
    family: AgentMeterWidgetCore.WidgetFamily,
    size: CGSize
) {
    let nowEpoch = FictionalFocusPresentationSource.nowEpoch
    for layout in IntentLayoutOption.allCases {
        let intent = configuredFocusIntent()
        intent.layout = layout
        intent.density = .comfortable
        let presentation = FictionalFocusPresentationSource.presentation(for: intent, family: family)
        assertSubstantiveRender(
            FocusWidgetView(presentation: presentation, nowEpoch: nowEpoch),
            size: size,
            colorScheme: .dark
        )
    }

    let comfortableIntent = configuredFocusIntent()
    comfortableIntent.layout = .automatic
    comfortableIntent.density = .comfortable
    let compactIntent = configuredFocusIntent()
    compactIntent.layout = .automatic
    compactIntent.density = .compact
    let comfortable = FictionalFocusPresentationSource.presentation(for: comfortableIntent, family: family)
    let compact = FictionalFocusPresentationSource.presentation(for: compactIntent, family: family)
    #expect(comfortable.configuration.density != compact.configuration.density)
    // Compact density visibly tightens the layout.
    #expect(renderedDifferenceRatio(
        FocusWidgetView(presentation: comfortable, nowEpoch: nowEpoch),
        FocusWidgetView(presentation: compact, nowEpoch: nowEpoch),
        size: size,
        region: CGRect(origin: .zero, size: size)
    ) > 0.001)
    assertSubstantiveRender(
        FocusWidgetView(presentation: compact, nowEpoch: nowEpoch),
        size: size,
        colorScheme: .light
    )
}

@MainActor
@Test func mediumFocusThirtyDayConfigurationsRenderAndExposeTheirModules() {
    for layout in IntentLayoutOption.allCases {
        for density in IntentDensityOption.allCases {
            let presentation = focusThirtyDayHeatMapPresentation(
                layout: layout,
                density: density,
                includesHistory: true,
                includesAdditionalWindows: true
            )
            assertSubstantiveRender(
                FocusWidgetView(presentation: presentation, nowEpoch: 1_799_900_000),
                size: CGSize(width: 360, height: 170),
                colorScheme: .dark
            )
        }
    }

    let mediumSize = CGSize(width: 360, height: 170)
    let largeSize = CGSize(width: 360, height: 380)
    let complete = focusThirtyDayHeatMapPresentation(
        layout: .expanded,
        density: .comfortable,
        includesHistory: true,
        includesAdditionalWindows: true
    )
    let withoutAdditionalWindows = focusThirtyDayHeatMapPresentation(
        layout: .expanded,
        density: .comfortable,
        includesHistory: true,
        includesAdditionalWindows: false
    )

    // Additional windows visibly change the medium canvas.
    #expect(renderedDifferenceRatio(
        FocusWidgetView(presentation: complete, nowEpoch: 1_799_900_000),
        FocusWidgetView(presentation: withoutAdditionalWindows, nowEpoch: 1_799_900_000),
        size: mediumSize,
        region: CGRect(origin: .zero, size: mediumSize)
    ) > 0.005)

    // The v2 focus renders the history module on the large canvas; removing
    // history must visibly change the rendering there.
    let largeComplete = focusThirtyDayHeatMapPresentation(
        layout: .expanded,
        density: .comfortable,
        includesHistory: true,
        includesAdditionalWindows: true,
        family: .large
    )
    let largeWithoutHistory = focusThirtyDayHeatMapPresentation(
        layout: .expanded,
        density: .comfortable,
        includesHistory: false,
        includesAdditionalWindows: true,
        family: .large
    )
    #expect(renderedDifferenceRatio(
        FocusWidgetView(presentation: largeComplete, nowEpoch: 1_799_900_000),
        FocusWidgetView(presentation: largeWithoutHistory, nowEpoch: 1_799_900_000),
        size: largeSize,
        region: CGRect(origin: .zero, size: largeSize)
    ) > 0.005)
}

@MainActor
@Test(arguments: [
    (AgentMeterWidgetCore.WidgetFamily.small, 0, CGSize(width: 170, height: 170)),
    (.medium, 2, CGSize(width: 360, height: 170)),
    (.large, 2, CGSize(width: 360, height: 380)),
    (.extraLarge, 4, CGSize(width: 720, height: 380)),
])
func focusFamiliesKeepTruthfulTimelineWindowCapacityAndRenderOverflowingWindows(
    family: AgentMeterWidgetCore.WidgetFamily,
    limit: Int,
    size: CGSize
) {
    let presentation = focusPresentationWithAdditionalWindows(family: family)

    // The timeline planner's per-family capacity model is unchanged by the
    // v2 redesign.
    #expect(FocusWindowCapacity.additionalLimit(for: family) == limit)
    #expect(presentation.providers.first?.additionalWindows.count == 6)
    assertSubstantiveRender(
        FocusWidgetView(presentation: presentation, nowEpoch: 1_799_900_000),
        size: size,
        colorScheme: .dark
    )
}

@MainActor
@Test(arguments: [
    (AgentMeterWidgetCore.WidgetFamily.small, IntentLayoutOption.automatic, CGSize(width: 170, height: 170)),
    (.large, .expanded, CGSize(width: 360, height: 380)),
])
func focusAbsoluteResetFallbackFitsNarrowResetColumns(
    family: AgentMeterWidgetCore.WidgetFamily,
    layout: IntentLayoutOption,
    size: CGSize
) {
    let presentation = focusResetFallbackPresentation(family: family, layout: layout)
    let nowEpoch = 1_799_900_000
    let semantics = ResetSummarySemantics(
        presentation: presentation.providers[0].rings[0],
        showsCountdown: false,
        showsAbsoluteDate: false,
        nowEpoch: nowEpoch
    )

    // The compact form is the narrow-column fallback: deterministic, single
    // line, and never longer than the long form.
    #expect(semantics.compactText == "⟳ 1d 3h")
    #expect(semantics.compactText.count <= WidgetResetPhrasing.longText(
        semantics.phrase,
        nowEpoch: nowEpoch
    ).count)
    assertSubstantiveRender(
        FocusWidgetView(presentation: presentation, nowEpoch: nowEpoch),
        size: size,
        colorScheme: .dark
    )
}

@Test func focusViewSourceDoesNotIntroduceScrolling() throws {
    let focusSource = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Focus/FocusWidgetView.swift")
    let source = try String(contentsOf: focusSource, encoding: .utf8)
    #expect(source.contains("ScrollView") == false)
}

@Test func dashboardPresentationsExposeAdditionalWindowsForSecondaryLines() {
    let intent = configuredDashboardIntent()
    let large = FictionalDashboardPresentationSource.presentation(for: intent, family: .large)
    let extraLarge = FictionalDashboardPresentationSource.presentation(for: intent, family: .extraLarge)

    // v2 rows surface secondary windows from the resolver's additionalWindows
    // — the data must be present at both families, never invented.
    #expect(large.providers.first?.additionalWindows.isEmpty == false)
    #expect(extraLarge.providers.first?.additionalWindows.isEmpty == false)
    #expect(extraLarge.providers.first?.additionalWindows.allSatisfy {
        $0.windowKind.isEmpty == false
    } == true)
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

    #expect(presentation.providers.map(\.name) == ["Gemini", "Agent unavailable", "Codex"])
    #expect(presentation.providers.map(\.availability) == [.available, .missing, .available])
    #expect(presentation.providers[1].id.contains("missing") == false)
    #expect(presentation.providers.map { $0.rings.map(\.displayedPercent) } == [[37, 79], [], [58, 82]])
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
        #expect(presentation.providers.count == 5)
        #expect(presentation.overflowCount == 3)
        #expect((presentation.history != nil) == (scenario.expectedHistoryStyle != .none))
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

private func presentationForLayout(
    _ layout: IntentLayoutOption,
    family: AgentMeterWidgetCore.WidgetFamily
) -> WidgetPresentation {
    let intent = configuredDashboardIntent()
    intent.layout = layout
    return FictionalDashboardPresentationSource.presentation(for: intent, family: family)
}

private func focusPresentationWithAdditionalWindows(
    family: AgentMeterWidgetCore.WidgetFamily
) -> WidgetPresentation {
    let configuration = IntentConfigurationAdapter.focus(configuredFocusIntent())
    let ring: (Int) -> WidgetRingPresentation = { index in
        WidgetRingPresentation(
            windowKind: "window-\(index)",
            label: "Window \(index)",
            usedPercent: 10 + index,
            displayedPercent: 10 + index,
            resetState: .scheduled(epoch: 1_800_000_000 + index)
        )
    }
    return WidgetPresentation(
        configuration: configuration,
        family: family,
        providers: [
            WidgetProviderPresentation(
                id: "codex",
                name: "Codex",
                status: "ok",
                rings: [ring(0), ring(1)],
                additionalWindows: (2..<8).map(ring)
            ),
        ],
        modules: [.usage, .primaryReset, .history],
        history: WidgetHistoryProjection(
            trendPoints: [
                WidgetTrendPoint(dayStartEpoch: 0, latestUsedPercent: 12),
                WidgetTrendPoint(dayStartEpoch: 86_400, latestUsedPercent: 42),
            ],
            windowKind: "window-0",
            windowLabel: "Window 0"
        ),
        freshness: .fresh,
        overflowCount: 0
    )
}

private func focusThirtyDayHeatMapPresentation(
    layout: IntentLayoutOption,
    density: IntentDensityOption,
    includesHistory: Bool,
    includesAdditionalWindows: Bool,
    family: AgentMeterWidgetCore.WidgetFamily = .medium
) -> WidgetPresentation {
    let intent = FocusWidgetIntent()
    intent.provider = ProviderEntity(id: "codex", name: "Codex")
    intent.outerWindow = WindowEntity(providerID: "codex", windowKind: "weekly", label: "Weekly")
    intent.innerWindow = WindowEntity(providerID: "codex", windowKind: "session", label: "Session")
    intent.historyStyle = includesHistory ? .heatMap : .none
    intent.historyRange = .days30
    intent.layout = layout
    intent.density = density
    intent.theme = .midnight
    intent.showResetCountdown = true
    intent.showAbsoluteResetDate = false
    let configuration = IntentConfigurationAdapter.focus(intent)
    let ring: (Int) -> WidgetRingPresentation = { index in
        WidgetRingPresentation(
            windowKind: "window-\(index)",
            label: index == 0 ? "Weekly" : (index == 1 ? "Session" : "Window \(index)"),
            usedPercent: 20 + index,
            displayedPercent: 20 + index,
            resetState: .scheduled(epoch: 1_800_000_000 + (index * 3_600))
        )
    }
    let additional = includesAdditionalWindows ? (2..<8).map(ring) : []
    let history = includesHistory ? WidgetHistoryProjection(
        cells: (0..<30).map { index in
            WidgetHeatMapCell(
                dayStartEpoch: index * 86_400,
                value: Double(index % 40),
                band: index.isMultiple(of: 5) ? .high : .moderate
            )
        },
        windowKind: "weekly",
        windowLabel: "Weekly"
    ) : nil
    return WidgetPresentation(
        configuration: configuration,
        family: family,
        providers: [
            WidgetProviderPresentation(
                id: "codex",
                name: "Codex",
                status: "ok",
                rings: [ring(0), ring(1)],
                additionalWindows: additional
            ),
        ],
        modules: configuration.modules,
        history: history,
        freshness: .fresh,
        overflowCount: 0
    )
}

private func focusResetFallbackPresentation(
    family: AgentMeterWidgetCore.WidgetFamily,
    layout: IntentLayoutOption
) -> WidgetPresentation {
    let intent = FocusWidgetIntent()
    intent.provider = ProviderEntity(id: "codex", name: "Codex")
    intent.outerWindow = WindowEntity(providerID: "codex", windowKind: "weekly", label: "Weekly")
    intent.innerWindow = WindowEntity(providerID: "codex", windowKind: "session", label: "Session")
    intent.historyStyle = .none
    intent.layout = layout
    intent.theme = .midnight
    intent.showResetCountdown = false
    intent.showAbsoluteResetDate = false
    let configuration = IntentConfigurationAdapter.focus(intent)
    let rings = [
        WidgetRingPresentation(
            windowKind: "weekly",
            label: "Weekly",
            usedPercent: 42,
            displayedPercent: 42,
            resetState: .scheduled(epoch: 1_800_000_000)
        ),
        WidgetRingPresentation(
            windowKind: "session",
            label: "Session",
            usedPercent: 18,
            displayedPercent: 18,
            resetState: .scheduled(epoch: 1_800_086_400)
        ),
    ]
    return WidgetPresentation(
        configuration: configuration,
        family: family,
        providers: [
            WidgetProviderPresentation(
                id: "codex",
                name: "Codex",
                status: "ok",
                rings: rings
            ),
        ],
        modules: configuration.modules,
        history: nil,
        freshness: .fresh,
        overflowCount: 0
    )
}

private func exceptionalHealthPresentation(
    kind: WidgetKind,
    family: AgentMeterWidgetCore.WidgetFamily
) -> WidgetPresentation {
    let configuration: WidgetRenderConfiguration
    switch kind {
    case .dashboard:
        configuration = IntentConfigurationAdapter.dashboard(DashboardWidgetIntent())
    case .focus:
        configuration = IntentConfigurationAdapter.focus(configuredFocusIntent())
    }
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
        usedPercent: 18,
        displayedPercent: 18,
        resetState: .scheduled(epoch: 1_800_003_600)
    )
    let additional = (0..<4).map { index in
        WidgetRingPresentation(
            windowKind: "additional-\(index)",
            label: "Additional \(index)",
            usedPercent: 20 + index,
            displayedPercent: 20 + index,
            resetState: .scheduled(epoch: 1_800_010_000 + index)
        )
    }
    let providerCount = kind == .dashboard ? family.maximumDashboardProviders : 1
    let providers = (0..<providerCount).map { index in
        WidgetProviderPresentation(
            id: "provider-\(index)",
            name: "Provider \(index)",
            status: "error at /private/path",
            healthState: .error,
            rings: [outer, inner],
            additionalWindows: additional
        )
    }
    let history = WidgetHistoryProjection(
        cells: (0..<30).map { index in
            WidgetHeatMapCell(
                dayStartEpoch: index * 86_400,
                value: Double(index % 41),
                band: .moderate
            )
        },
        trendPoints: (0..<7).map { index in
            WidgetTrendPoint(dayStartEpoch: index * 86_400, latestUsedPercent: 20 + index)
        },
        windowKind: "weekly",
        windowLabel: "Weekly"
    )
    return WidgetPresentation(
        configuration: configuration,
        family: family,
        providers: providers,
        modules: configuration.modules,
        history: history,
        freshness: .stale,
        overflowCount: 0
    )
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
            let alpha = UInt32((color.alphaComponent * 15).rounded())
            colors.insert((red << 12) | (green << 8) | (blue << 4) | alpha)
        }
    }

    // The v2 language is flatter and airier than v1 (fewer hues, more
    // whitespace), so substance is measured as: at least 4% of the canvas
    // carries content, across at least 6 distinct rendered color+alpha
    // levels. A blank or single-tone canvas still fails both.
    #expect(Double(nontransparentCount) / Double(max(sampleCount, 1)) >= 0.04)
    #expect(colors.count >= 6)
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

@MainActor
private func dashboardBodyContainsLink(_ view: DashboardWidgetView) -> Bool {
    _ = view
    if String(reflecting: DashboardWidgetView.Body.self).contains("SwiftUI.Link") {
        return true
    }
    // Fallback: the opaque body type may not expose nested generics — the
    // provider rows are wrapped in Link(destination:) at the source level.
    let source = try? String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Dashboard/DashboardWidgetView.swift"),
        encoding: .utf8
    )
    return source?.contains("Link(destination:") == true
}
