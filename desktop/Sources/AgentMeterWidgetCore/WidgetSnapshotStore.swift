import Darwin
import Foundation

public enum WidgetSnapshotStoreError: Error, Equatable, Sendable {
    case encodedSizeExceedsLimit
    case unsupportedSchema(Int)
}

public struct WidgetSnapshotStore: Sendable {
    public static let fileName = "widget-snapshot-v1.json"
    public static let maximumBytes = 262_144

    public let url: URL

    public init(directoryURL: URL) {
        url = directoryURL.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    public func load() throws -> WidgetSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let byteCount = attributes[.size] as? NSNumber,
           byteCount.intValue > Self.maximumBytes {
            throw WidgetSnapshotStoreError.encodedSizeExceedsLimit
        }

        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumBytes else {
            throw WidgetSnapshotStoreError.encodedSizeExceedsLimit
        }
        let header = try JSONDecoder().decode(SchemaHeader.self, from: data)
        guard header.schemaVersion == WidgetSnapshot.schemaVersion else {
            throw WidgetSnapshotStoreError.unsupportedSchema(header.schemaVersion)
        }
        return try JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    public func writeIfChanged(_ snapshot: WidgetSnapshot) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        guard data.count <= Self.maximumBytes else {
            throw WidgetSnapshotStoreError.encodedSizeExceedsLimit
        }
        if let existing = try? Data(contentsOf: url), existing == data {
            return false
        }

        let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(
            ".\(Self.fileName).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let descriptor = Darwin.open(temporaryURL.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw currentPOSIXError() }

        var handle: FileHandle? = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle?.close() }
        try handle?.write(contentsOf: data)
        guard Darwin.fchmod(descriptor, 0o600) == 0 else { throw currentPOSIXError() }
        try handle?.synchronize()
        try handle?.close()
        handle = nil

        guard Darwin.rename(temporaryURL.path, url.path) == 0 else {
            throw currentPOSIXError()
        }
        return true
    }

    private func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private struct SchemaHeader: Decodable {
    let schemaVersion: Int
}
