import Foundation

public struct ProviderWindow: Codable, Equatable, Identifiable, Sendable {
    public let kind: String
    public let label: String
    public let usedPercent: Int?
    public let resetAtEpoch: Int?

    public var id: String { kind }

    public init(kind: String, label: String, usedPercent: Int?, resetAtEpoch: Int?) {
        self.kind = kind
        self.label = label
        self.usedPercent = usedPercent
        self.resetAtEpoch = resetAtEpoch
    }
}

public struct ProviderSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let status: String
    public let windows: [ProviderWindow]
    public let updatedAtEpoch: Int?
    public let errorCode: String?

    public init(
        id: String,
        name: String,
        status: String,
        windows: [ProviderWindow],
        updatedAtEpoch: Int? = nil,
        errorCode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.windows = windows
        self.updatedAtEpoch = updatedAtEpoch
        self.errorCode = errorCode
    }
}
