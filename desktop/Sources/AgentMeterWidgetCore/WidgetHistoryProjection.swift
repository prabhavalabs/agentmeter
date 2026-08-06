import AgentMeterCore
import Foundation

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

public struct WidgetTrendPoint: Equatable, Sendable {
    public let dayStartEpoch: Int
    public let latestUsedPercent: Int?

    public init(dayStartEpoch: Int, latestUsedPercent: Int?) {
        self.dayStartEpoch = dayStartEpoch
        self.latestUsedPercent = latestUsedPercent
    }
}

public struct WidgetHistoryProjection: Equatable, Sendable {
    public let cells: [WidgetHeatMapCell]
    public let trendPoints: [WidgetTrendPoint]
    public let windowKind: String?
    public let windowLabel: String?
    public let availabilityMessage: String?

    public init(
        cells: [WidgetHeatMapCell] = [],
        trendPoints: [WidgetTrendPoint] = [],
        windowKind: String? = nil,
        windowLabel: String? = nil,
        availabilityMessage: String? = nil
    ) {
        self.cells = cells
        self.trendPoints = trendPoints
        self.windowKind = windowKind
        self.windowLabel = windowLabel
        self.availabilityMessage = availabilityMessage
    }

    public static func heatMap(
        providers: [WidgetProviderSnapshot],
        range: WidgetHistoryPeriod,
        scope: WidgetHeatMapScope,
        selectedProviderID: String? = nil,
        windowKind: String? = nil,
        endingAtDayEpoch: Int,
        calendar: Calendar = .current
    ) -> [WidgetHeatMapCell] {
        let selected = selectedProviders(
            providers,
            scope: scope,
            selectedProviderID: selectedProviderID
        )
        let valuesByProvider = selected.map { provider in
            valuesByDay(provider: provider, windowKind: windowKind)
        }
        let dayEpochs = dayEpochs(
            count: range.dayCount,
            endingAtDayEpoch: endingAtDayEpoch,
            calendar: calendar
        )

        return dayEpochs.map { epoch in
            let available = valuesByProvider.compactMap { $0[epoch] }
            guard available.isEmpty == false else {
                return WidgetHeatMapCell(dayStartEpoch: epoch, value: nil, band: nil)
            }
            let value = available.reduce(0, +) / Double(available.count)
            return WidgetHeatMapCell(dayStartEpoch: epoch, value: value, band: band(for: value))
        }
    }

    public static func trend(
        provider: WidgetProviderSnapshot,
        range: WidgetHistoryPeriod,
        windowKind: String,
        endingAtDayEpoch: Int,
        calendar: Calendar = .current
    ) -> [WidgetTrendPoint] {
        let values = provider.history.reduce(into: [Int: Int]()) { result, day in
            guard day.providerId == provider.id,
                  day.windowKind == windowKind,
                  let latestUsedPercent = day.latestUsedPercent,
                  (0...100).contains(latestUsedPercent) else { return }
            result[day.dayStartEpoch] = latestUsedPercent
        }

        return dayEpochs(
            count: range.dayCount,
            endingAtDayEpoch: endingAtDayEpoch,
            calendar: calendar
        ).map {
            WidgetTrendPoint(dayStartEpoch: $0, latestUsedPercent: values[$0])
        }
    }

    private static func dayEpochs(
        count: Int,
        endingAtDayEpoch: Int,
        calendar: Calendar
    ) -> [Int] {
        let endingDay = calendar.startOfDay(
            for: Date(timeIntervalSince1970: TimeInterval(endingAtDayEpoch))
        )
        var dates = [endingDay]
        while dates.count < count {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: dates[0]) else {
                return []
            }
            dates.insert(previous, at: 0)
        }
        return dates.map { Int($0.timeIntervalSince1970) }
    }

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
