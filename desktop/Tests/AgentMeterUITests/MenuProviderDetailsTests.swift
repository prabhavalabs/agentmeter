import AgentMeterCore
import AgentMeterUI
import Testing

@Test func providerExpansionTogglesEachAgentIndependently() {
    var expansion = MenuProviderExpansion()

    expansion.toggle("claude")
    expansion.toggle("codex")

    #expect(expansion.contains("claude"))
    #expect(expansion.contains("codex"))

    expansion.toggle("claude")

    #expect(expansion.contains("claude") == false)
    #expect(expansion.contains("codex"))
}

@Test func claudeDetailsSeparateSessionCycleAndReportedModels() {
    let provider = ProviderSummary(
        id: "claude",
        name: "Claude",
        status: "ok",
        windows: [
            ProviderWindow(kind: "session", label: "Session", usedPercent: 16, resetAtEpoch: 2_000),
            ProviderWindow(kind: "weekly", label: "Weekly", usedPercent: 7, resetAtEpoch: 3_000),
            ProviderWindow(kind: "claude-weekly-fable", label: "Fable only", usedPercent: 8, resetAtEpoch: 3_000),
        ]
    )

    let details = MenuProviderDetails(provider: provider)

    #expect(details.sessionWindow?.label == "Session")
    #expect(details.cycleWindow?.label == "Weekly")
    #expect(details.modelWindows.map(\.label) == ["Fable only"])
}

@Test func modelBasedProvidersKeepEveryReportedWindowInTheBreakdown() {
    let provider = ProviderSummary(
        id: "gemini",
        name: "Gemini",
        status: "ok",
        windows: [
            ProviderWindow(kind: "session", label: "Pro", usedPercent: 2, resetAtEpoch: 2_000),
            ProviderWindow(kind: "weekly", label: "Flash", usedPercent: 4, resetAtEpoch: 2_000),
            ProviderWindow(kind: "tertiary", label: "Flash Lite", usedPercent: 1, resetAtEpoch: 2_000),
        ]
    )

    let details = MenuProviderDetails(provider: provider)

    #expect(details.sessionWindow == nil)
    #expect(details.cycleWindow == nil)
    #expect(details.modelWindows.map(\.label) == ["Pro", "Flash", "Flash Lite"])
}
