import Foundation

public struct WidgetHistoryDay: Codable, Equatable, Sendable {
    public let providerId: String
    public let windowKind: String
    public let dayStartEpoch: Int
    public let consumedPercentPoints: Int
    public let latestUsedPercent: Int?
    public let resetAtEpoch: Int?

    public init(
        providerId: String,
        windowKind: String,
        dayStartEpoch: Int,
        consumedPercentPoints: Int,
        latestUsedPercent: Int?,
        resetAtEpoch: Int?
    ) {
        self.providerId = providerId
        self.windowKind = windowKind
        self.dayStartEpoch = dayStartEpoch
        self.consumedPercentPoints = consumedPercentPoints
        self.latestUsedPercent = latestUsedPercent
        self.resetAtEpoch = resetAtEpoch
    }
}

public struct WidgetHistorySummary: Codable, Equatable, Sendable {
    public let historyStartEpoch: Int?
    public let days: [WidgetHistoryDay]

    public init(historyStartEpoch: Int?, days: [WidgetHistoryDay]) {
        self.historyStartEpoch = historyStartEpoch
        self.days = days
    }
}
