import AgentMeterCore

public enum WidgetHeatBand: String, Codable, Equatable, Sendable, CaseIterable {
    case zero
    case low
    case moderate
    case high
    case veryHigh
}

public struct WidgetHeatMapCell: Equatable, Sendable {
    public let dayStartEpoch: Int
    public let value: Double?
    public let band: WidgetHeatBand?

    public var hasData: Bool { value != nil }

    public init(dayStartEpoch: Int, value: Double?, band: WidgetHeatBand?) {
        self.dayStartEpoch = dayStartEpoch
        self.value = value
        self.band = band
    }
}

public struct WidgetHistoryProjection: Equatable, Sendable {
    public let cells: [WidgetHeatMapCell]
    public let availabilityMessage: String?

    public init(cells: [WidgetHeatMapCell], availabilityMessage: String? = nil) {
        self.cells = cells
        self.availabilityMessage = availabilityMessage
    }

    public static func heatMap(
        providers: [WidgetProviderSnapshot],
        range: WidgetHistoryPeriod,
        scope: WidgetHeatMapScope,
        selectedProviderID: String? = nil,
        windowKind: String? = nil,
        endingAtDayEpoch: Int
    ) -> [WidgetHeatMapCell] {
        let selected = selectedProviders(
            providers,
            scope: scope,
            selectedProviderID: selectedProviderID
        )
        let valuesByProvider = selected.map { provider in
            valuesByDay(provider: provider, windowKind: windowKind)
        }
        let start = endingAtDayEpoch - (range.dayCount - 1) * secondsPerDay

        return (0..<range.dayCount).map { offset in
            let epoch = start + offset * secondsPerDay
            let available = valuesByProvider.compactMap { $0[epoch] }
            guard available.isEmpty == false else {
                return WidgetHeatMapCell(dayStartEpoch: epoch, value: nil, band: nil)
            }
            let value = available.reduce(0, +) / Double(available.count)
            return WidgetHeatMapCell(dayStartEpoch: epoch, value: value, band: band(for: value))
        }
    }

    private static let secondsPerDay = 86_400

    private static func selectedProviders(
        _ providers: [WidgetProviderSnapshot],
        scope: WidgetHeatMapScope,
        selectedProviderID: String?
    ) -> [WidgetProviderSnapshot] {
        switch scope {
        case .combined:
            return providers
        case .singleProvider:
            guard let selectedProviderID else { return Array(providers.prefix(1)) }
            return providers.filter { $0.id == selectedProviderID }
        }
    }

    private static func valuesByDay(
        provider: WidgetProviderSnapshot,
        windowKind: String?
    ) -> [Int: Double] {
        let resolvedKind = windowKind ?? provider.windows.lazy
            .map(\.kind)
            .first { kind in provider.history.contains { $0.windowKind == kind } }
        guard let resolvedKind else { return [:] }

        return provider.history.reduce(into: [:]) { values, day in
            guard day.providerId == provider.id, day.windowKind == resolvedKind else { return }
            values[day.dayStartEpoch] = Double(day.consumedPercentPoints)
        }
    }

    private static func band(for value: Double) -> WidgetHeatBand {
        switch value {
        case 0:
            return .zero
        case ...5:
            return .low
        case ...15:
            return .moderate
        case ...30:
            return .high
        default:
            return .veryHigh
        }
    }
}
