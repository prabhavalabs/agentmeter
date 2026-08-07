import AgentMeterCore

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let maximumProviderCount = 8
    public static let maximumWindowCountPerProvider = 8
    public static let maximumHistoryWindowCountPerProvider = 4
    public static let maximumHistoryDayCount = 30
    public static let maximumHourlyPointCountPerWindow = 26
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
    public let hourly: [WidgetHourlyPoint]

    public init(
        id: String,
        name: String,
        status: String,
        updatedAtEpoch: Int?,
        windows: [WidgetWindowSnapshot],
        history: [WidgetHistoryDay],
        hourly: [WidgetHourlyPoint] = []
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.updatedAtEpoch = updatedAtEpoch
        self.windows = windows
        self.history = history
        self.hourly = hourly
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        status = try container.decode(String.self, forKey: .status)
        updatedAtEpoch = try container.decodeIfPresent(Int.self, forKey: .updatedAtEpoch)
        windows = try container.decode([WidgetWindowSnapshot].self, forKey: .windows)
        history = try container.decode([WidgetHistoryDay].self, forKey: .history)
        // Absent in snapshots written before the hourly trend existed.
        hourly = try container.decodeIfPresent([WidgetHourlyPoint].self, forKey: .hourly) ?? []
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
