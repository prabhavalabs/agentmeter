import Foundation

public struct UsageHistorySample: Codable, Equatable, Identifiable, Sendable {
    public let providerId: String
    public let windowKind: String
    public let sampledAtEpoch: Int
    public let usedPercent: Int?
    public let resetAtEpoch: Int?

    public var id: String {
        "\(providerId):\(windowKind):\(sampledAtEpoch)"
    }

    public init(
        providerId: String,
        windowKind: String,
        sampledAtEpoch: Int,
        usedPercent: Int?,
        resetAtEpoch: Int?
    ) {
        self.providerId = providerId
        self.windowKind = windowKind
        self.sampledAtEpoch = sampledAtEpoch
        self.usedPercent = usedPercent
        self.resetAtEpoch = resetAtEpoch
    }
}

public struct UsageHistoryResult: Codable, Equatable, Sendable {
    public let usage: [UsageHistorySample]

    public init(usage: [UsageHistorySample]) {
        self.usage = usage
    }
}
