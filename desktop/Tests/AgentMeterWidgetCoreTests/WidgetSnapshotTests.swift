import AgentMeterCore
import Foundation
import Testing
@testable import AgentMeterWidgetCore

@Test func snapshotEnforcesSchemaAndCollectionBounds() throws {
    let snapshot = try WidgetSnapshotBuilder().build(
        state: makeWidgetState(providerCount: 10, windowsPerProvider: 10),
        summaries: makeHistorySummaries(providerCount: 10, windowCount: 6, dayCount: 35)
    )

    #expect(snapshot.schemaVersion == 1)
    #expect(snapshot.providers.map(\.id) == (0..<8).map { "provider-\($0)" })
    #expect(snapshot.providers.allSatisfy { $0.windows.count == 8 })
    #expect(snapshot.providers.allSatisfy { provider in
        Set(provider.history.map(\.windowKind)).count == 4
    })
    #expect(snapshot.providers.allSatisfy { provider in
        Set(provider.history.map(\.dayStartEpoch)).count == 30
    })
    #expect(snapshot.pollIntervalSeconds == 300)
    let encoded = try JSONEncoder().encode(snapshot)
    #expect(encoded.count <= WidgetSnapshot.maximumEncodedBytes)
}

@Test func snapshotPreservesConfiguredOrderAndUsesLatestRefreshTime() throws {
    let state = makeWidgetState(
        providerCount: 3,
        windowsPerProvider: 1,
        configuredProviderIds: ["provider-2", "provider-0", "missing", "provider-1"],
        lastProviderRefreshEpoch: 9_000,
        providerUpdatedAtEpochs: [8_500, 9_500, nil]
    )

    let first = try WidgetSnapshotBuilder().build(state: state, summaries: [:])
    let second = try WidgetSnapshotBuilder().build(state: state, summaries: [:])

    #expect(first.providers.map(\.id) == ["provider-2", "provider-0", "provider-1"])
    #expect(first.generatedAtEpoch == 9_500)
    #expect(first == second)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let firstData = try encoder.encode(first)
    let secondData = try encoder.encode(second)
    #expect(firstData == secondData)
}

@Test func snapshotClampsInvalidCurrentPercentagesAndPreservesUnknowns() throws {
    let provider = ProviderSummary(
        id: "codex",
        name: "Codex",
        status: "ready",
        windows: [
            ProviderWindow(kind: "negative", label: "Negative", usedPercent: -1, resetAtEpoch: 1_000),
            ProviderWindow(kind: "unknown", label: "Unknown", usedPercent: nil, resetAtEpoch: nil),
            ProviderWindow(kind: "valid", label: "Valid", usedPercent: 100, resetAtEpoch: 2_000),
            ProviderWindow(kind: "overflow", label: "Overflow", usedPercent: 101, resetAtEpoch: 3_000),
        ],
        updatedAtEpoch: nil
    )
    let state = ControlState(
        revision: 1,
        connection: ConnectionState(phase: .connected),
        providers: [provider],
        bridge: BridgeStatus(version: "1", running: true, configuredProviderIds: ["codex"])
    )

    let windows = try WidgetSnapshotBuilder().build(state: state, summaries: [:]).providers[0].windows

    #expect(windows.map(\.usedPercent) == [nil, nil, 100, nil])
    #expect(windows[1].resetAtEpoch == nil)
}

@Test func snapshotEncodingOmitsPrivateControlStateFields() throws {
    let email = "private@example.com"
    let prompt = "Summarize my unreleased acquisition plan"
    let repositoryPath = "/Users/private/secret-repository"
    let oauthToken = "oauth-secret-token-123"
    let provider = ProviderSummary(
        id: "codex",
        name: "Codex",
        status: "ready",
        windows: [ProviderWindow(kind: "weekly", label: "Weekly", usedPercent: 25, resetAtEpoch: nil)],
        updatedAtEpoch: 4_000,
        errorCode: "\(email)|\(prompt)|\(repositoryPath)|\(oauthToken)"
    )
    let state = ControlState(
        revision: 1,
        connection: ConnectionState(phase: .connected),
        providers: [provider],
        bridge: BridgeStatus(
            version: prompt,
            running: true,
            lastProviderRefreshEpoch: 4_000,
            lastErrorCode: oauthToken,
            providerHealth: [repositoryPath: email],
            configuredProviderIds: ["codex"]
        )
    )

    let data = try JSONEncoder().encode(WidgetSnapshotBuilder().build(state: state, summaries: [:]))
    let encoded = try #require(String(data: data, encoding: .utf8))

    #expect(encoded.contains(email) == false)
    #expect(encoded.contains(prompt) == false)
    #expect(encoded.contains(repositoryPath) == false)
    #expect(encoded.contains(oauthToken) == false)
}

@Test func snapshotRejectsPayloadsOverTheEncodedLimit() throws {
    let oversizedName = String(repeating: "x", count: WidgetSnapshot.maximumEncodedBytes)
    let provider = ProviderSummary(
        id: "codex",
        name: oversizedName,
        status: "ready",
        windows: [],
        updatedAtEpoch: 4_000
    )
    let state = ControlState(
        revision: 1,
        connection: ConnectionState(phase: .connected),
        providers: [provider],
        bridge: BridgeStatus(version: "1", running: true, configuredProviderIds: ["codex"])
    )

    #expect(throws: WidgetSnapshotBuilder.Error.encodedSizeExceedsLimit) {
        try WidgetSnapshotBuilder().build(state: state, summaries: [:])
    }
}

@Test func snapshotOmitsHistoryForTruncatedCurrentWindows() throws {
    let state = makeWidgetState(providerCount: 1, windowsPerProvider: 9)
    let summary = WidgetHistorySummary(
        historyStartEpoch: 20_000,
        days: [
            WidgetHistoryDay(
                providerId: "provider-0",
                windowKind: "window-8",
                dayStartEpoch: 20_000,
                consumedPercentPoints: 10,
                latestUsedPercent: nil,
                resetAtEpoch: nil
            ),
        ]
    )

    let snapshot = try WidgetSnapshotBuilder().build(
        state: state,
        summaries: ["provider-0": summary]
    )

    #expect(snapshot.providers[0].windows.map(\.kind).contains("window-8") == false)
    #expect(snapshot.providers[0].history.isEmpty)
}

@Test func snapshotOmitsStrayRowsOutsideTheFourPriorityHistoryWindows() throws {
    let state = makeWidgetState(providerCount: 1, windowsPerProvider: 5)
    let summary = WidgetHistorySummary(
        historyStartEpoch: 20_000,
        days: [
            WidgetHistoryDay(
                providerId: "provider-0",
                windowKind: "window-4",
                dayStartEpoch: 20_000,
                consumedPercentPoints: 10,
                latestUsedPercent: nil,
                resetAtEpoch: nil
            ),
        ]
    )

    let snapshot = try WidgetSnapshotBuilder().build(
        state: state,
        summaries: ["provider-0": summary]
    )

    #expect(snapshot.providers[0].history.isEmpty)
}

@Test func snapshotConvertsInvalidHistoricalLatestPercentagesToUnknown() throws {
    let history = try buildHistory([
        historyDay(dayStartEpoch: 20_000, consumedPercentPoints: 10, latestUsedPercent: -1),
        historyDay(dayStartEpoch: 106_400, consumedPercentPoints: 20, latestUsedPercent: 101),
        historyDay(dayStartEpoch: 192_800, consumedPercentPoints: 30, latestUsedPercent: nil),
    ])

    #expect(history.count == 3)
    #expect(history.allSatisfy { $0.latestUsedPercent == nil })
}

@Test func snapshotOmitsNegativeHistoricalConsumptionInsteadOfInventingZero() throws {
    let history = try buildHistory([
        historyDay(dayStartEpoch: 20_000, consumedPercentPoints: -1, latestUsedPercent: 25),
        historyDay(dayStartEpoch: 106_400, consumedPercentPoints: 0, latestUsedPercent: 25),
    ])

    #expect(history.map(\.dayStartEpoch) == [106_400])
    #expect(history.map(\.consumedPercentPoints) == [0])
}

@Test func snapshotPreservesHistoricalConsumptionAboveOneHundred() throws {
    let history = try buildHistory([
        historyDay(dayStartEpoch: 20_000, consumedPercentPoints: 175, latestUsedPercent: 75),
    ])

    #expect(history.map(\.consumedPercentPoints) == [175])
}

private func buildHistory(_ days: [WidgetHistoryDay]) throws -> [WidgetHistoryDay] {
    let snapshot = try WidgetSnapshotBuilder().build(
        state: makeWidgetState(providerCount: 1, windowsPerProvider: 1),
        summaries: [
            "provider-0": WidgetHistorySummary(historyStartEpoch: 20_000, days: days),
        ]
    )
    return snapshot.providers[0].history
}

private func historyDay(
    dayStartEpoch: Int,
    consumedPercentPoints: Int,
    latestUsedPercent: Int?
) -> WidgetHistoryDay {
    WidgetHistoryDay(
        providerId: "provider-0",
        windowKind: "window-0",
        dayStartEpoch: dayStartEpoch,
        consumedPercentPoints: consumedPercentPoints,
        latestUsedPercent: latestUsedPercent,
        resetAtEpoch: nil
    )
}

private func makeWidgetState(
    providerCount: Int,
    windowsPerProvider: Int,
    configuredProviderIds: [String]? = nil,
    lastProviderRefreshEpoch: Int? = 7_000,
    providerUpdatedAtEpochs: [Int?] = []
) -> ControlState {
    let providers = (0..<providerCount).map { providerIndex in
        ProviderSummary(
            id: "provider-\(providerIndex)",
            name: "Provider \(providerIndex)",
            status: "ready",
            windows: (0..<windowsPerProvider).map { windowIndex in
                ProviderWindow(
                    kind: "window-\(windowIndex)",
                    label: "Window \(windowIndex)",
                    usedPercent: windowIndex,
                    resetAtEpoch: 10_000 + windowIndex
                )
            },
            updatedAtEpoch: providerIndex < providerUpdatedAtEpochs.count
                ? providerUpdatedAtEpochs[providerIndex]
                : 6_000 + providerIndex
        )
    }
    return ControlState(
        revision: 1,
        connection: ConnectionState(phase: .connected),
        providers: providers,
        bridge: BridgeStatus(
            version: "1",
            running: true,
            lastProviderRefreshEpoch: lastProviderRefreshEpoch,
            configuredProviderIds: configuredProviderIds ?? providers.map(\.id),
            pollIntervalSeconds: 300
        )
    )
}

private func makeHistorySummaries(
    providerCount: Int,
    windowCount: Int,
    dayCount: Int
) -> [String: WidgetHistorySummary] {
    Dictionary(uniqueKeysWithValues: (0..<providerCount).map { providerIndex in
        let providerId = "provider-\(providerIndex)"
        let days = (0..<dayCount).flatMap { dayIndex in
            (0..<windowCount).map { windowIndex in
                WidgetHistoryDay(
                    providerId: providerId,
                    windowKind: "window-\(windowIndex)",
                    dayStartEpoch: 20_000 + dayIndex * 86_400,
                    consumedPercentPoints: dayIndex,
                    latestUsedPercent: nil,
                    resetAtEpoch: nil
                )
            }
        }
        return (providerId, WidgetHistorySummary(historyStartEpoch: 20_000, days: days))
    })
}
