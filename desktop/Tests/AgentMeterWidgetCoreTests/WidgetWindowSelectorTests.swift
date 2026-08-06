import AgentMeterCore
import Testing
@testable import AgentMeterWidgetCore

@Test func monthlyAndSessionArePreferredRingWindows() {
    let selection = WidgetWindowSelector.select(from: [
        window("daily", "Daily"),
        window("session", "Session"),
        window("monthly", "Monthly"),
    ])

    #expect(selection.outer?.kind == "monthly")
    #expect(selection.inner?.kind == "session")
    #expect(selection.additional.map(\.kind) == ["daily"])
}

@Test func exactWeeklyOutranksModelSpecificWeekly() {
    let selection = WidgetWindowSelector.select(from: [
        window("session", "Session"),
        window("claude-weekly-opus", "Opus weekly"),
        window("weekly", "Weekly"),
    ])

    #expect(selection.outer?.kind == "weekly")
    #expect(selection.inner?.kind == "session")
}

@Test func normalizedLabelsCanExpressBillingAndShortWindows() {
    let selection = WidgetWindowSelector.select(from: [
        window("plan-cycle", " Billing cycle "),
        window("rolling-limit", "Short-term"),
    ])

    #expect(selection.outer?.kind == "plan-cycle")
    #expect(selection.inner?.kind == "rolling-limit")
}

@Test func oneWindowFallbackKeepsRingsDistinct() {
    let selection = WidgetWindowSelector.select(from: [window("daily", "Daily")])

    #expect(selection.outer?.kind == "daily")
    #expect(selection.inner == nil)
    #expect(selection.additional.isEmpty)
}

@Test func missingPercentagesDoNotRemoveEligibleWindows() {
    let selection = WidgetWindowSelector.select(from: [
        window("weekly", "Weekly", usedPercent: nil),
        window("session", "Session", usedPercent: nil),
    ])

    #expect(selection.outer?.kind == "weekly")
    #expect(selection.inner?.kind == "session")
}

@Test func focusOverridesApplyOnlyToKindsOnTheProvider() {
    let windows = [
        window("session", "Session"),
        window("weekly", "Weekly"),
        window("daily", "Daily"),
    ]

    let valid = WidgetWindowSelector.select(
        from: windows,
        focusOuterKind: " DAILY ",
        focusInnerKind: "weekly"
    )
    let invalid = WidgetWindowSelector.select(
        from: windows,
        focusOuterKind: "monthly",
        focusInnerKind: "unknown"
    )

    #expect(valid.outer?.kind == "daily")
    #expect(valid.inner?.kind == "weekly")
    #expect(invalid.outer?.kind == "weekly")
    #expect(invalid.inner?.kind == "session")
}

@Test func identicalFocusOverridesStillChooseDistinctRingsWhenPossible() {
    let selection = WidgetWindowSelector.select(
        from: [window("weekly", "Weekly"), window("session", "Session")],
        focusOuterKind: "weekly",
        focusInnerKind: "weekly"
    )

    #expect(selection.outer?.kind == "weekly")
    #expect(selection.inner?.kind == "session")
}

private func window(_ kind: String, _ label: String, usedPercent: Int? = 50) -> ProviderWindow {
    ProviderWindow(kind: kind, label: label, usedPercent: usedPercent, resetAtEpoch: nil)
}
