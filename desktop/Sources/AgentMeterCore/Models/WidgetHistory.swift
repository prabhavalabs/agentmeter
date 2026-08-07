import Foundation

public struct WidgetHistoryDay: Codable, Equatable, Sendable {
    public let providerId: String
    public let windowKind: String
    public let dayStartEpoch: Int
    public let consumedPercentPoints: Int
    public let latestUsedPercent: Int?
    public let resetAtEpoch: Int?
    public let cycleStartEpoch: Int?

    public init(
        providerId: String,
        windowKind: String,
        dayStartEpoch: Int,
        consumedPercentPoints: Int,
        latestUsedPercent: Int?,
        resetAtEpoch: Int?,
        cycleStartEpoch: Int? = nil
    ) {
        self.providerId = providerId
        self.windowKind = windowKind
        self.dayStartEpoch = dayStartEpoch
        self.consumedPercentPoints = consumedPercentPoints
        self.latestUsedPercent = latestUsedPercent
        self.resetAtEpoch = resetAtEpoch
        self.cycleStartEpoch = cycleStartEpoch
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

public struct WidgetHourlyPoint: Codable, Equatable, Sendable {
    public let providerId: String
    public let windowKind: String
    public let hourStartEpoch: Int
    public let latestUsedPercent: Int
    public let resetAtEpoch: Int?

    public init(
        providerId: String,
        windowKind: String,
        hourStartEpoch: Int,
        latestUsedPercent: Int,
        resetAtEpoch: Int?
    ) {
        self.providerId = providerId
        self.windowKind = windowKind
        self.hourStartEpoch = hourStartEpoch
        self.latestUsedPercent = latestUsedPercent
        self.resetAtEpoch = resetAtEpoch
    }
}

public struct WidgetHourlySummary: Codable, Equatable, Sendable {
    public let hours: [WidgetHourlyPoint]

    public init(hours: [WidgetHourlyPoint]) {
        self.hours = hours
    }
}
