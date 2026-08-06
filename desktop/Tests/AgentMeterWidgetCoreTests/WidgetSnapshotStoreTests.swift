import AgentMeterCore
import Foundation
import Testing
@testable import AgentMeterWidgetCore

@Test func snapshotStoreRoundTripsCanonicalSnapshot() throws {
    try withTemporaryDirectory { directory in
        let store = WidgetSnapshotStore(directoryURL: directory)
        let snapshot = makeSnapshot()

        #expect(try store.writeIfChanged(snapshot))
        #expect(try store.load() == snapshot)

        let storedData = try Data(contentsOf: store.url)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(storedData == (try encoder.encode(snapshot)))
    }
}

@Test func snapshotStoreUsesOwnerReadWritePermissions() throws {
    try withTemporaryDirectory { directory in
        let store = WidgetSnapshotStore(directoryURL: directory)

        _ = try store.writeIfChanged(makeSnapshot())

        let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o600)
    }
}

@Test func snapshotStoreSkipsByteIdenticalWrites() throws {
    try withTemporaryDirectory { directory in
        let store = WidgetSnapshotStore(directoryURL: directory)
        let snapshot = makeSnapshot()

        let firstWriteChanged = try store.writeIfChanged(snapshot)
        let secondWriteChanged = try store.writeIfChanged(snapshot)
        #expect(firstWriteChanged)
        #expect(secondWriteChanged == false)
    }
}

@Test func snapshotStoreRejectsOversizedWritesWithoutReplacingCurrentSnapshot() throws {
    try withTemporaryDirectory { directory in
        let store = WidgetSnapshotStore(directoryURL: directory)
        let original = makeSnapshot()
        _ = try store.writeIfChanged(original)
        let oversized = WidgetSnapshot(
            generatedAtEpoch: 2_000,
            pollIntervalSeconds: 300,
            historyStartEpoch: nil,
            providers: [
                WidgetProviderSnapshot(
                    id: "codex",
                    name: String(repeating: "x", count: WidgetSnapshotStore.maximumBytes),
                    status: "ready",
                    updatedAtEpoch: nil,
                    windows: [],
                    history: []
                ),
            ]
        )

        #expect(throws: WidgetSnapshotStoreError.encodedSizeExceedsLimit) {
            try store.writeIfChanged(oversized)
        }
        #expect(try store.load() == original)
    }
}

@Test func snapshotStoreRejectsOversizedFilesBeforeDecoding() throws {
    try withTemporaryDirectory { directory in
        let store = WidgetSnapshotStore(directoryURL: directory)
        let oversized = Data(repeating: UInt8(ascii: "x"), count: WidgetSnapshotStore.maximumBytes + 1)
        try oversized.write(to: store.url)

        #expect(throws: WidgetSnapshotStoreError.encodedSizeExceedsLimit) {
            try store.load()
        }
    }
}

@Test func snapshotStoreCleansTemporaryFileWhenCommitFails() throws {
    try withTemporaryDirectory { directory in
        let store = WidgetSnapshotStore(directoryURL: directory)
        try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: false)
        try Data("sentinel".utf8).write(to: store.url.appendingPathComponent("keep"))

        #expect(throws: (any Error).self) {
            try store.writeIfChanged(makeSnapshot())
        }

        let siblingNames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(siblingNames == [WidgetSnapshotStore.fileName])
        #expect(FileManager.default.fileExists(atPath: store.url.appendingPathComponent("keep").path))
    }
}

@Test func snapshotStorePreservesCurrentFileWhenWritingTemporaryFileFails() throws {
    try withTemporaryDirectory { directory in
        let store = WidgetSnapshotStore(directoryURL: directory)
        let original = makeSnapshot()
        _ = try store.writeIfChanged(original)
        let originalData = try Data(contentsOf: store.url)

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }

        #expect(throws: (any Error).self) {
            try store.writeIfChanged(makeSnapshot(generatedAtEpoch: 2_000))
        }
        #expect(try Data(contentsOf: store.url) == originalData)
    }
}

@Test func snapshotStoreRejectsUnsupportedSchemaBeforePayloadDecoding() throws {
    try withTemporaryDirectory { directory in
        let store = WidgetSnapshotStore(directoryURL: directory)
        let futurePayload = Data(#"{"schemaVersion":2,"providers":"not-an-array"}"#.utf8)
        try futurePayload.write(to: store.url)

        #expect(throws: WidgetSnapshotStoreError.unsupportedSchema(2)) {
            try store.load()
        }
    }
}

@Test func snapshotStoreRejectsSchemaOnePayloadsThatExceedStructuralCaps() throws {
    try withTemporaryDirectory { directory in
        let store = WidgetSnapshotStore(directoryURL: directory)
        let tooManyProviders = WidgetSnapshot(
            generatedAtEpoch: 1_000,
            pollIntervalSeconds: 300,
            historyStartEpoch: nil,
            providers: (0...WidgetSnapshot.maximumProviderCount).map { index in
                WidgetProviderSnapshot(
                    id: "provider-\(index)",
                    name: "Provider \(index)",
                    status: "ready",
                    updatedAtEpoch: nil,
                    windows: [],
                    history: []
                )
            }
        )
        try JSONEncoder().encode(tooManyProviders).write(to: store.url)

        #expect(throws: WidgetSnapshotValidationError.tooManyProviders) {
            try store.load()
        }
    }
}

@Test func snapshotStoreRejectsTooManyHistoryCellsPerKind() throws {
    try withTemporaryDirectory { directory in
        let store = WidgetSnapshotStore(directoryURL: directory)
        let history = (0...WidgetSnapshot.maximumHistoryDayCount).map { index in
            WidgetHistoryDay(
                providerId: "codex",
                windowKind: "weekly",
                dayStartEpoch: 100 + index * 86_400,
                consumedPercentPoints: index,
                latestUsedPercent: index,
                resetAtEpoch: nil
            )
        }
        let snapshot = makeSnapshot(history: history)
        try JSONEncoder().encode(snapshot).write(to: store.url)

        #expect(throws: WidgetSnapshotValidationError.tooManyHistoryCells(
            providerID: "codex",
            kind: "weekly"
        )) {
            try store.load()
        }
    }
}

@Test func snapshotStoreRejectsTooManyWindowsAndHistoryKinds() throws {
    try withTemporaryDirectory { directory in
        let store = WidgetSnapshotStore(directoryURL: directory)
        let windows = (0...WidgetSnapshot.maximumWindowCountPerProvider).map { index in
            WidgetWindowSnapshot(
                kind: "window-\(index)",
                label: "Window \(index)",
                usedPercent: index,
                resetAtEpoch: nil
            )
        }
        let tooManyWindows = WidgetSnapshot(
            generatedAtEpoch: 1_000,
            pollIntervalSeconds: 300,
            historyStartEpoch: nil,
            providers: [
                WidgetProviderSnapshot(
                    id: "codex",
                    name: "Codex",
                    status: "ready",
                    updatedAtEpoch: nil,
                    windows: windows,
                    history: []
                ),
            ]
        )
        try JSONEncoder().encode(tooManyWindows).write(to: store.url)
        #expect(throws: WidgetSnapshotValidationError.tooManyWindows(providerID: "codex")) {
            try store.load()
        }

        let retainedWindows = Array(windows.prefix(5))
        let tooManyKinds = WidgetSnapshot(
            generatedAtEpoch: 1_000,
            pollIntervalSeconds: 300,
            historyStartEpoch: nil,
            providers: [
                WidgetProviderSnapshot(
                    id: "codex",
                    name: "Codex",
                    status: "ready",
                    updatedAtEpoch: nil,
                    windows: retainedWindows,
                    history: retainedWindows.enumerated().map { index, window in
                        WidgetHistoryDay(
                            providerId: "codex",
                            windowKind: window.kind,
                            dayStartEpoch: 100 + index * 86_400,
                            consumedPercentPoints: index,
                            latestUsedPercent: index,
                            resetAtEpoch: nil
                        )
                    }
                ),
            ]
        )
        try JSONEncoder().encode(tooManyKinds).write(to: store.url)
        #expect(throws: WidgetSnapshotValidationError.tooManyHistoryKinds(providerID: "codex")) {
            try store.load()
        }
    }
}

@Test func snapshotStoreRejectsMismatchedAndUnknownHistoryRows() throws {
    try withTemporaryDirectory { directory in
        let store = WidgetSnapshotStore(directoryURL: directory)
        let mismatch = makeSnapshot(history: [
            WidgetHistoryDay(
                providerId: "claude",
                windowKind: "weekly",
                dayStartEpoch: 100,
                consumedPercentPoints: 1,
                latestUsedPercent: 1,
                resetAtEpoch: nil
            ),
        ])
        try JSONEncoder().encode(mismatch).write(to: store.url)
        #expect(throws: WidgetSnapshotValidationError.mismatchedHistoryProvider(
            providerID: "codex"
        )) {
            try store.load()
        }

        let unknown = makeSnapshot(history: [
            WidgetHistoryDay(
                providerId: "codex",
                windowKind: "monthly",
                dayStartEpoch: 100,
                consumedPercentPoints: 1,
                latestUsedPercent: 1,
                resetAtEpoch: nil
            ),
        ])
        try JSONEncoder().encode(unknown).write(to: store.url)
        #expect(throws: WidgetSnapshotValidationError.unknownHistoryWindow(
            providerID: "codex",
            kind: "monthly"
        )) {
            try store.load()
        }
    }
}

@Test func snapshotStoreCanonicalizesDuplicateHistoryCellsAndStableBytes() throws {
    try withTemporaryDirectory { directory in
        let store = WidgetSnapshotStore(directoryURL: directory)
        let low = storeHistoryDay(consumed: 3, latest: 20, reset: nil, cycleStart: nil)
        let high = storeHistoryDay(consumed: 7, latest: 30, reset: 4_000, cycleStart: 90)
        let first = makeSnapshot(history: [low, high])
        let second = makeSnapshot(history: [high, low])

        #expect(try store.writeIfChanged(first))
        let firstBytes = try Data(contentsOf: store.url)
        #expect(try store.load()?.providers[0].history == [high])
        #expect(try store.writeIfChanged(second) == false)
        #expect(try Data(contentsOf: store.url) == firstBytes)
    }
}

@Test func snapshotStoreRejectsInvalidWritesWithoutReplacingTheCurrentSnapshot() throws {
    try withTemporaryDirectory { directory in
        let store = WidgetSnapshotStore(directoryURL: directory)
        let original = makeSnapshot()
        _ = try store.writeIfChanged(original)
        let invalid = WidgetSnapshot(
            generatedAtEpoch: 2_000,
            pollIntervalSeconds: 300,
            historyStartEpoch: nil,
            providers: original.providers + (1...WidgetSnapshot.maximumProviderCount).map { index in
                WidgetProviderSnapshot(
                    id: "provider-\(index)",
                    name: "Provider \(index)",
                    status: "ready",
                    updatedAtEpoch: nil,
                    windows: [],
                    history: []
                )
            }
        )

        #expect(throws: WidgetSnapshotValidationError.tooManyProviders) {
            try store.writeIfChanged(invalid)
        }
        #expect(try store.load() == original)
    }
}

private func makeSnapshot(
    generatedAtEpoch: Int = 1_000,
    history: [WidgetHistoryDay]? = nil
) -> WidgetSnapshot {
    WidgetSnapshot(
        generatedAtEpoch: generatedAtEpoch,
        pollIntervalSeconds: 300,
        historyStartEpoch: 100,
        providers: [
            WidgetProviderSnapshot(
                id: "codex",
                name: "Codex",
                status: "ready",
                updatedAtEpoch: 900,
                windows: [
                    WidgetWindowSnapshot(
                        kind: "weekly",
                        label: "Weekly",
                        usedPercent: 25,
                        resetAtEpoch: 4_000
                    ),
                ],
                history: history ?? [
                    WidgetHistoryDay(
                        providerId: "codex",
                        windowKind: "weekly",
                        dayStartEpoch: 100,
                        consumedPercentPoints: 5,
                        latestUsedPercent: 25,
                        resetAtEpoch: 4_000
                    ),
                ]
            ),
        ]
    )
}

private func storeHistoryDay(
    consumed: Int,
    latest: Int?,
    reset: Int?,
    cycleStart: Int?
) -> WidgetHistoryDay {
    WidgetHistoryDay(
        providerId: "codex",
        windowKind: "weekly",
        dayStartEpoch: 100,
        consumedPercentPoints: consumed,
        latestUsedPercent: latest,
        resetAtEpoch: reset,
        cycleStartEpoch: cycleStart
    )
}

private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("WidgetSnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}
