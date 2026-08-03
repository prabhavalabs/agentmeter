import Foundation

public struct UsageHistoryQuery: Equatable, Sendable {
    public let sinceEpoch: Int
    public let bucketSeconds: Int?
    public let currentCycle: Bool

    public init(sinceEpoch: Int, bucketSeconds: Int?, currentCycle: Bool) {
        self.sinceEpoch = sinceEpoch
        self.bucketSeconds = bucketSeconds
        self.currentCycle = currentCycle
    }
}

public enum UsageHistoryRange: String, CaseIterable, Identifiable, Sendable {
    case last24Hours
    case last7Days
    case last30Days
    case currentCycle

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .last24Hours: "Last 24 hours"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        case .currentCycle: "Current cycle"
        }
    }

    public func query(
        now: Date = .now,
        calendar: Calendar = .current
    ) -> UsageHistoryQuery {
        let nowEpoch = Int(now.timeIntervalSince1970)
        switch self {
        case .last24Hours:
            let startOfHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            let start = calendar.date(byAdding: .hour, value: -23, to: startOfHour) ?? startOfHour
            return UsageHistoryQuery(
                sinceEpoch: max(0, Int(start.timeIntervalSince1970)),
                bucketSeconds: 3_600,
                currentCycle: false
            )
        case .last7Days:
            let startOfToday = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
            return UsageHistoryQuery(
                sinceEpoch: max(0, Int(start.timeIntervalSince1970)),
                bucketSeconds: 86_400,
                currentCycle: false
            )
        case .last30Days:
            let startOfToday = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
            return UsageHistoryQuery(
                sinceEpoch: max(0, Int(start.timeIntervalSince1970)),
                bucketSeconds: 86_400,
                currentCycle: false
            )
        case .currentCycle:
            return UsageHistoryQuery(
                sinceEpoch: max(0, nowEpoch - 30 * 86_400),
                bucketSeconds: nil,
                currentCycle: true
            )
        }
    }
}

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
