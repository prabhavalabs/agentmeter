import AgentMeterCore

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let maximumProviderCount = 8
    public static let maximumWindowCountPerProvider = 8
    public static let maximumHistoryWindowCountPerProvider = 4
    public static let maximumHistoryDayCount = 30
    public static let maximumEncodedBytes = 256 * 1_024

    public let schemaVersion: Int
    public let generatedAtEpoch: Int
    public let pollIntervalSeconds: Int
    public let historyStartEpoch: Int?
    public let providers: [WidgetProviderSnapshot]

    public init(
        schemaVersion: Int = WidgetSnapshot.schemaVersion,
        generatedAtEpoch: Int,
        pollIntervalSeconds: Int,
        historyStartEpoch: Int?,
        providers: [WidgetProviderSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAtEpoch = generatedAtEpoch
        self.pollIntervalSeconds = pollIntervalSeconds
        self.historyStartEpoch = historyStartEpoch
        self.providers = providers
    }
}

public struct WidgetProviderSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let status: String
    public let updatedAtEpoch: Int?
    public let windows: [WidgetWindowSnapshot]
    public let history: [WidgetHistoryDay]

    public init(
        id: String,
        name: String,
        status: String,
        updatedAtEpoch: Int?,
        windows: [WidgetWindowSnapshot],
        history: [WidgetHistoryDay]
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.updatedAtEpoch = updatedAtEpoch
        self.windows = windows
        self.history = history
    }
}

public struct WidgetWindowSnapshot: Codable, Equatable, Identifiable, Sendable {
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
