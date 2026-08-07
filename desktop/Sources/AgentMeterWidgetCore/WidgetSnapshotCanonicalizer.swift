import AgentMeterCore
import Foundation

public enum WidgetSnapshotValidationError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case tooManyProviders
    case duplicateProviderID(String)
    case tooManyWindows(providerID: String)
    case duplicateWindowKind(providerID: String, kind: String)
    case tooManyHistoryKinds(providerID: String)
    case tooManyHistoryCells(providerID: String, kind: String)
    case mismatchedHistoryProvider(providerID: String)
    case unknownHistoryWindow(providerID: String, kind: String)
    case tooManyHourlyPoints(providerID: String, kind: String)
    case mismatchedHourlyProvider(providerID: String)
    case unknownHourlyWindow(providerID: String, kind: String)
    case invalidValue
}

public enum WidgetSnapshotCanonicalizer {
    public static func canonicalize(_ snapshot: WidgetSnapshot) throws -> WidgetSnapshot {
        guard snapshot.schemaVersion == WidgetSnapshot.schemaVersion else {
            throw WidgetSnapshotValidationError.unsupportedSchema(snapshot.schemaVersion)
        }
        guard snapshot.providers.count <= WidgetSnapshot.maximumProviderCount else {
            throw WidgetSnapshotValidationError.tooManyProviders
        }
        guard snapshot.generatedAtEpoch >= 0,
              snapshot.historyStartEpoch.map({ $0 >= 0 }) ?? true else {
            throw WidgetSnapshotValidationError.invalidValue
        }

        var providerIDs = Set<String>()
        let providers = try snapshot.providers.map { provider in
            guard provider.id.isEmpty == false,
                  providerIDs.insert(provider.id).inserted else {
                if provider.id.isEmpty {
                    throw WidgetSnapshotValidationError.invalidValue
                }
                throw WidgetSnapshotValidationError.duplicateProviderID(provider.id)
            }
            return try canonicalProvider(provider)
        }

        return WidgetSnapshot(
            schemaVersion: snapshot.schemaVersion,
            generatedAtEpoch: snapshot.generatedAtEpoch,
            pollIntervalSeconds: snapshot.pollIntervalSeconds,
            historyStartEpoch: snapshot.historyStartEpoch,
            providers: providers
        )
    }

    static func preferredHistoryDay(
        _ first: WidgetHistoryDay,
        _ second: WidgetHistoryDay
    ) -> WidgetHistoryDay {
        isPreferred(second, over: first) ? second : first
    }

    private static func canonicalProvider(
        _ provider: WidgetProviderSnapshot
    ) throws -> WidgetProviderSnapshot {
        guard provider.windows.count <= WidgetSnapshot.maximumWindowCountPerProvider else {
            throw WidgetSnapshotValidationError.tooManyWindows(providerID: provider.id)
        }
        guard provider.updatedAtEpoch.map({ $0 >= 0 }) ?? true else {
            throw WidgetSnapshotValidationError.invalidValue
        }

        var windowKinds = Set<String>()
        for window in provider.windows {
            guard window.kind.isEmpty == false else {
                throw WidgetSnapshotValidationError.invalidValue
            }
            guard windowKinds.insert(window.kind).inserted else {
                throw WidgetSnapshotValidationError.duplicateWindowKind(
                    providerID: provider.id,
                    kind: window.kind
                )
            }
            guard window.usedPercent.map({ (0...100).contains($0) }) ?? true,
                  window.resetAtEpoch.map({ $0 >= 0 }) ?? true else {
                throw WidgetSnapshotValidationError.invalidValue
            }
        }

        var historyKinds = Set<String>()
        var cells: [HistoryCellKey: WidgetHistoryDay] = [:]
        for day in provider.history {
            guard day.providerId == provider.id else {
                throw WidgetSnapshotValidationError.mismatchedHistoryProvider(
                    providerID: provider.id
                )
            }
            guard windowKinds.contains(day.windowKind) else {
                throw WidgetSnapshotValidationError.unknownHistoryWindow(
                    providerID: provider.id,
                    kind: day.windowKind
                )
            }
            guard day.dayStartEpoch >= 0,
                  day.consumedPercentPoints >= 0,
                  day.latestUsedPercent.map({ (0...100).contains($0) }) ?? true,
                  day.resetAtEpoch.map({ $0 >= 0 }) ?? true,
                  day.cycleStartEpoch.map({ $0 >= 0 }) ?? true else {
                throw WidgetSnapshotValidationError.invalidValue
            }
            historyKinds.insert(day.windowKind)
            let key = HistoryCellKey(
                windowKind: day.windowKind,
                dayStartEpoch: day.dayStartEpoch
            )
            if let existing = cells[key] {
                cells[key] = preferredHistoryDay(existing, day)
            } else {
                cells[key] = day
            }
        }
        guard historyKinds.count <= WidgetSnapshot.maximumHistoryWindowCountPerProvider else {
            throw WidgetSnapshotValidationError.tooManyHistoryKinds(providerID: provider.id)
        }
        for kind in historyKinds {
            let count = cells.keys.filter { $0.windowKind == kind }.count
            guard count <= WidgetSnapshot.maximumHistoryDayCount else {
                throw WidgetSnapshotValidationError.tooManyHistoryCells(
                    providerID: provider.id,
                    kind: kind
                )
            }
        }

        var hourlyPoints: [HourlyPointKey: WidgetHourlyPoint] = [:]
        for point in provider.hourly {
            guard point.providerId == provider.id else {
                throw WidgetSnapshotValidationError.mismatchedHourlyProvider(
                    providerID: provider.id
                )
            }
            guard windowKinds.contains(point.windowKind) else {
                throw WidgetSnapshotValidationError.unknownHourlyWindow(
                    providerID: provider.id,
                    kind: point.windowKind
                )
            }
            guard point.hourStartEpoch >= 0,
                  (0...100).contains(point.latestUsedPercent),
                  point.resetAtEpoch.map({ $0 >= 0 }) ?? true else {
                throw WidgetSnapshotValidationError.invalidValue
            }
            let key = HourlyPointKey(
                windowKind: point.windowKind,
                hourStartEpoch: point.hourStartEpoch
            )
            hourlyPoints[key] = point
        }
        for kind in Set(hourlyPoints.keys.map(\.windowKind)) {
            let count = hourlyPoints.keys.filter { $0.windowKind == kind }.count
            guard count <= WidgetSnapshot.maximumHourlyPointCountPerWindow else {
                throw WidgetSnapshotValidationError.tooManyHourlyPoints(
                    providerID: provider.id,
                    kind: kind
                )
            }
        }

        let windowOrder = Dictionary(
            uniqueKeysWithValues: provider.windows.enumerated().map { ($1.kind, $0) }
        )
        let history = cells.values.sorted { left, right in
            if left.dayStartEpoch != right.dayStartEpoch {
                return left.dayStartEpoch < right.dayStartEpoch
            }
            let leftOrder = windowOrder[left.windowKind] ?? .max
            let rightOrder = windowOrder[right.windowKind] ?? .max
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return left.windowKind < right.windowKind
        }
        let hourly = hourlyPoints.values.sorted { left, right in
            if left.hourStartEpoch != right.hourStartEpoch {
                return left.hourStartEpoch < right.hourStartEpoch
            }
            let leftOrder = windowOrder[left.windowKind] ?? .max
            let rightOrder = windowOrder[right.windowKind] ?? .max
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return left.windowKind < right.windowKind
        }

        return WidgetProviderSnapshot(
            id: provider.id,
            name: provider.name,
            status: provider.status,
            updatedAtEpoch: provider.updatedAtEpoch,
            windows: provider.windows,
            history: history,
            hourly: hourly
        )
    }

    private static func isPreferred(
        _ candidate: WidgetHistoryDay,
        over current: WidgetHistoryDay
    ) -> Bool {
        if candidate.consumedPercentPoints != current.consumedPercentPoints {
            return candidate.consumedPercentPoints > current.consumedPercentPoints
        }
        if let preference = optionalPreference(
            candidate.latestUsedPercent,
            over: current.latestUsedPercent
        ) {
            return preference
        }
        if let preference = optionalPreference(candidate.resetAtEpoch, over: current.resetAtEpoch) {
            return preference
        }
        return optionalPreference(candidate.cycleStartEpoch, over: current.cycleStartEpoch) ?? false
    }

    private static func optionalPreference(_ candidate: Int?, over current: Int?) -> Bool? {
        guard candidate != current else { return nil }
        guard let candidate else { return false }
        guard let current else { return true }
        return candidate > current
    }
}

private struct HistoryCellKey: Hashable {
    let windowKind: String
    let dayStartEpoch: Int
}

private struct HourlyPointKey: Hashable {
    let windowKind: String
    let hourStartEpoch: Int
}

enum WidgetSnapshotCoding {
    static func encode(_ snapshot: WidgetSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }
}
