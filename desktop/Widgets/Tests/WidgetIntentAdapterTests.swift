import AgentMeterWidgetCore
import Testing

@Test func dashboardDefaultsPreserveEveryVisibleChoice() {
    let configuration = IntentConfigurationAdapter.dashboard(DashboardWidgetIntent())

    #expect(configuration.kind == .dashboard)
    #expect(configuration.providerIDs == [])
    #expect(configuration.focusProviderID == nil)
    #expect(configuration.percentageMode == .used)
    #expect(configuration.modules == [.usage, .primaryReset, .history])
    #expect(configuration.historyStyle == .heatMap)
    #expect(configuration.historyPeriod == .days30)
    #expect(configuration.heatMapScope == .combined)
    #expect(configuration.trendWindow == .outer)
    #expect(configuration.layout == .usageAndRings)
    #expect(configuration.density == .comfortable)
    #expect(configuration.theme == .system)
    #expect(configuration.tapDestination == .overview)
    #expect(configuration.showsResetCountdown)
    #expect(!configuration.showsAbsoluteResetDate)
}

@Test func focusMappingPreservesProviderWindowsAndPresentationChoices() {
    let intent = FocusWidgetIntent()
    intent.provider = ProviderEntity(id: "codex", name: "Codex")
    intent.outerWindow = WindowEntity(providerID: "codex", windowKind: "weekly", label: "Weekly")
    intent.innerWindow = WindowEntity(providerID: "codex", windowKind: "session", label: "Session")
    intent.percentage = .remaining
    intent.historyStyle = .trend
    intent.historyRange = .days7
    intent.heatScope = .singleProvider
    intent.trendWindow = .inner
    intent.layout = .expanded
    intent.density = .compact
    intent.theme = .midnight
    intent.tapDestination = .providerDetail
    intent.showResetCountdown = false
    intent.showAbsoluteResetDate = true
    intent.showStatus = true
    intent.showFreshness = true

    let configuration = IntentConfigurationAdapter.focus(intent)

    #expect(configuration.kind == .focus)
    #expect(configuration.providerIDs == ["codex"])
    #expect(configuration.focusProviderID == "codex")
    #expect(configuration.outerWindowKind == "weekly")
    #expect(configuration.innerWindowKind == "session")
    #expect(configuration.percentageMode == .remaining)
    #expect(configuration.modules == [.usage, .primaryReset, .history, .status, .freshness])
    #expect(configuration.historyStyle == .trend)
    #expect(configuration.historyPeriod == .days7)
    #expect(configuration.heatMapScope == .singleProvider)
    #expect(configuration.trendWindow == .inner)
    #expect(configuration.layout == .expanded)
    #expect(configuration.density == .compact)
    #expect(configuration.theme == .midnight)
    #expect(configuration.tapDestination == .providerDetail)
    #expect(!configuration.showsResetCountdown)
    #expect(configuration.showsAbsoluteResetDate)
}

@Test func approvedThemesRemainDistinctThroughIntentMapping() {
    let intent = FocusWidgetIntent()
    let cases: [(IntentThemeOption, WidgetTheme)] = [
        (.system, .system),
        (.midnight, .midnight),
        (.neutral, .neutral),
        (.providerTinted, .providerTinted),
    ]

    for (intentTheme, expectedTheme) in cases {
        intent.theme = intentTheme
        #expect(IntentConfigurationAdapter.focus(intent).theme == expectedTheme)
    }
}

@Test func tapIntentExposesOnlyRoutableDestinations() {
    #expect(Set(IntentTapDestinationOption.allCases) == [.overview, .providerDetail, .agents])
}

@Test func fictionalFocusSourceAppliesProviderWindowsAndRemainingMode() {
    let intent = FocusWidgetIntent()
    intent.provider = ProviderEntity(id: "claude", name: "Claude")
    intent.outerWindow = WindowEntity(providerID: "claude", windowKind: "monthly", label: "Monthly")
    intent.innerWindow = WindowEntity(providerID: "claude", windowKind: "session", label: "Session")
    intent.percentage = .remaining

    let presentation = FictionalFocusPresentationSource.presentation(
        for: intent,
        family: .large
    )

    #expect(presentation.providers.first?.id == "claude")
    #expect(presentation.providers.first?.rings.map(\.windowKind) == ["monthly", "session"])
    #expect(presentation.providers.first?.rings.map(\.displayedPercent) == [67, 76])
    #expect(presentation.configuration.percentageMode == .remaining)
}

@Test func fictionalFocusSourceAppliesHistoryThemeResetModulesAndTapChoices() {
    let intent = FocusWidgetIntent()
    intent.provider = ProviderEntity(id: "gemini", name: "Gemini")
    intent.historyStyle = .none
    intent.theme = .providerTinted
    intent.tapDestination = .agents
    intent.showResetCountdown = false
    intent.showAbsoluteResetDate = true
    intent.showStatus = true
    intent.showFreshness = true

    let presentation = FictionalFocusPresentationSource.presentation(
        for: intent,
        family: .large
    )

    #expect(presentation.providers.first?.id == "gemini")
    #expect(presentation.history == nil)
    #expect(!presentation.modules.contains(.history))
    #expect(presentation.modules.contains(.status))
    #expect(presentation.modules.contains(.freshness))
    #expect(presentation.configuration.theme == .providerTinted)
    #expect(presentation.configuration.tapDestination == .agents)
    #expect(!presentation.configuration.showsResetCountdown)
    #expect(presentation.configuration.showsAbsoluteResetDate)
}

@Test func fictionalFocusSourceFallsBackSafelyForUnknownProvider() {
    let intent = FocusWidgetIntent()
    intent.provider = ProviderEntity(id: "private-account", name: "Private Account")

    let presentation = FictionalFocusPresentationSource.presentation(
        for: intent,
        family: .small
    )

    #expect(presentation.providers.first?.id == "codex")
    #expect(presentation.providers.first?.name == "Codex")
}

@Test func focusMappingRejectsWindowsFromAnotherProvider() {
    let intent = FocusWidgetIntent()
    intent.provider = ProviderEntity(id: "codex", name: "Codex")
    intent.outerWindow = WindowEntity(providerID: "claude", windowKind: "weekly", label: "Weekly")
    intent.innerWindow = WindowEntity(providerID: "codex", windowKind: "session", label: "Session")

    let configuration = IntentConfigurationAdapter.focus(intent)

    #expect(configuration.outerWindowKind == nil)
    #expect(configuration.innerWindowKind == "session")
}

@Test func focusSpecificTrendWindowMapsOnlyForTheSelectedProvider() {
    let intent = FocusWidgetIntent()
    intent.provider = ProviderEntity(id: "codex", name: "Codex")
    intent.trendWindow = .focus
    intent.specificTrendWindow = WindowEntity(
        providerID: "codex",
        windowKind: "weekly",
        label: "Weekly"
    )

    let matching = IntentConfigurationAdapter.focus(intent)

    #expect(matching.trendWindow == .focus)
    #expect(matching.trendFocusWindowKind == "weekly")

    intent.specificTrendWindow = WindowEntity(
        providerID: "claude",
        windowKind: "monthly",
        label: "Monthly"
    )

    let mismatched = IntentConfigurationAdapter.focus(intent)

    #expect(mismatched.trendWindow == .focus)
    #expect(mismatched.trendFocusWindowKind == nil)
}

@Test func dashboardAllHistoryAndTapOptionsMapWithoutConflation() {
    let intent = DashboardWidgetIntent()
    intent.providers = [
        ProviderEntity(id: "claude", name: "Claude"),
        ProviderEntity(id: "codex", name: "Codex"),
    ]
    intent.historyStyle = .none
    intent.tapDestination = .agents
    intent.layout = .compact

    let configuration = IntentConfigurationAdapter.dashboard(intent)

    #expect(configuration.providerIDs == ["claude", "codex"])
    #expect(!configuration.modules.contains(.history))
    #expect(configuration.historyStyle == .none)
    #expect(configuration.tapDestination == .agents)
    #expect(configuration.layout == .compact)
}

@Test func providerQueryPreservesSnapshotOrderAndOmitsUnknownIDs() async throws {
    let query = ProviderEntityQuery(loader: { entitySnapshot() })

    let suggested = try await query.suggestedEntities()
    let resolved = try await query.entities(for: ["claude", "missing", "codex"])

    #expect(suggested.map(\.id) == ["codex", "claude"])
    #expect(suggested.map(\.name) == ["Codex", "Claude"])
    #expect(resolved.map(\.id) == ["codex", "claude"])
}

@Test func windowQueryFiltersSuggestionsToFocusProviderAndPreservesWindowOrder() async throws {
    let query = WindowEntityQuery(loader: { entitySnapshot() }, selectedProviderID: "claude")

    let suggested = try await query.suggestedEntities()
    let resolved = try await query.entities(for: ["codex:weekly", "missing:daily", "claude:monthly"])

    #expect(suggested.map(\.id) == ["claude:monthly", "claude:session"])
    #expect(suggested.map(\.label) == ["Monthly", "Session"])
    #expect(resolved.map(\.id) == ["codex:weekly", "claude:monthly"])
}

@Test func entityQueriesOmitAmbiguousCompositeIDsAndKeepValidSiblingOrder() async throws {
    let providers = ProviderEntityQuery(loader: { ambiguousEntitySnapshot() })
    let windows = WindowEntityQuery(loader: { ambiguousEntitySnapshot() }, selectedProviderID: "a")

    let suggestedProviders = try await providers.suggestedEntities()
    let suggestedWindows = try await windows.suggestedEntities()
    let resolvedAmbiguousID = try await windows.entities(
        for: ["a:b:c", "beta:monthly", "a:weekly"]
    )

    #expect(suggestedProviders.map(\.id) == ["a", "beta"])
    #expect(suggestedWindows.map(\.id) == ["a:weekly"])
    #expect(resolvedAmbiguousID.map(\.id) == ["a:weekly", "beta:monthly"])
}

@Test func entityQueriesFailClosedWhenTheSnapshotLoaderIsMissingOrThrows() async throws {
    let missingProviders = ProviderEntityQuery(loader: { nil })
    let corruptWindows = WindowEntityQuery(loader: { throw EntityLoaderFailure.corrupt })

    #expect(try await missingProviders.suggestedEntities().isEmpty)
    #expect(try await missingProviders.entities(for: ["codex"]).isEmpty)
    #expect(try await corruptWindows.suggestedEntities().isEmpty)
    #expect(try await corruptWindows.entities(for: ["codex:weekly"]).isEmpty)
}

private enum EntityLoaderFailure: Error {
    case corrupt
}

private func entitySnapshot() -> WidgetSnapshot {
    WidgetSnapshot(
        generatedAtEpoch: 1_000,
        pollIntervalSeconds: 300,
        historyStartEpoch: nil,
        providers: [
            WidgetProviderSnapshot(
                id: "codex",
                name: "Codex",
                status: "error at /private/path",
                updatedAtEpoch: 999,
                windows: [
                    WidgetWindowSnapshot(kind: "weekly", label: "Weekly", usedPercent: 42, resetAtEpoch: 2_000),
                    WidgetWindowSnapshot(kind: "session", label: "Session", usedPercent: 8, resetAtEpoch: 1_500),
                ],
                history: []
            ),
            WidgetProviderSnapshot(
                id: "claude",
                name: "Claude",
                status: "ok",
                updatedAtEpoch: 998,
                windows: [
                    WidgetWindowSnapshot(kind: "monthly", label: "Monthly", usedPercent: 11, resetAtEpoch: nil),
                    WidgetWindowSnapshot(kind: "session", label: "Session", usedPercent: nil, resetAtEpoch: nil),
                ],
                history: []
            ),
        ]
    )
}

private func ambiguousEntitySnapshot() -> WidgetSnapshot {
    WidgetSnapshot(
        generatedAtEpoch: 1_000,
        pollIntervalSeconds: 300,
        historyStartEpoch: nil,
        providers: [
            WidgetProviderSnapshot(
                id: "a",
                name: "A",
                status: "ok",
                updatedAtEpoch: nil,
                windows: [
                    WidgetWindowSnapshot(kind: "b:c", label: "Ambiguous One", usedPercent: nil, resetAtEpoch: nil),
                    WidgetWindowSnapshot(kind: "weekly", label: "Weekly", usedPercent: nil, resetAtEpoch: nil),
                ],
                history: []
            ),
            WidgetProviderSnapshot(
                id: "a:b",
                name: "Ambiguous Two",
                status: "ok",
                updatedAtEpoch: nil,
                windows: [
                    WidgetWindowSnapshot(kind: "c", label: "Ambiguous Two", usedPercent: nil, resetAtEpoch: nil),
                ],
                history: []
            ),
            WidgetProviderSnapshot(
                id: "",
                name: "Empty",
                status: "ok",
                updatedAtEpoch: nil,
                windows: [
                    WidgetWindowSnapshot(kind: "daily", label: "Daily", usedPercent: nil, resetAtEpoch: nil),
                ],
                history: []
            ),
            WidgetProviderSnapshot(
                id: "Codex",
                name: "Not Normalized",
                status: "ok",
                updatedAtEpoch: nil,
                windows: [
                    WidgetWindowSnapshot(kind: "session", label: "Session", usedPercent: nil, resetAtEpoch: nil),
                ],
                history: []
            ),
            WidgetProviderSnapshot(
                id: "beta",
                name: "Beta",
                status: "ok",
                updatedAtEpoch: nil,
                windows: [
                    WidgetWindowSnapshot(kind: "", label: "Empty Kind", usedPercent: nil, resetAtEpoch: nil),
                    WidgetWindowSnapshot(kind: "monthly", label: "Monthly", usedPercent: nil, resetAtEpoch: nil),
                ],
                history: []
            ),
        ]
    )
}
