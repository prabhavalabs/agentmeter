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

private func makeSnapshot(generatedAtEpoch: Int = 1_000) -> WidgetSnapshot {
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
                history: [
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

private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("WidgetSnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}
