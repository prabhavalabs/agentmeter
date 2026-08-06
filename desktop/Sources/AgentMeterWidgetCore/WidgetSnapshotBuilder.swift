import AgentMeterCore
import Foundation

public struct WidgetSnapshotBuilder: Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case encodedSizeExceedsLimit
    }

    public init() {}

    public func build(
        state: ControlState,
        summaries: [String: WidgetHistorySummary]
    ) throws -> WidgetSnapshot {
        let providers = orderedProviders(in: state)
            .prefix(WidgetSnapshot.maximumProviderCount)
            .map { provider in
                let windows = provider.windows
                    .prefix(WidgetSnapshot.maximumWindowCountPerProvider)
                    .map(makeWindowSnapshot)
                return WidgetProviderSnapshot(
                    id: provider.id,
                    name: provider.name,
                    status: provider.status,
                    updatedAtEpoch: provider.updatedAtEpoch,
                    windows: windows,
                    history: history(for: provider, summary: summaries[provider.id])
                )
            }

        let snapshot = WidgetSnapshot(
            generatedAtEpoch: generationEpoch(state: state),
            pollIntervalSeconds: state.bridge.pollIntervalSeconds,
            historyStartEpoch: historyStartEpoch(
                providerIds: providers.map(\.id),
                summaries: summaries
            ),
            providers: providers
        )
        guard try JSONEncoder().encode(snapshot).count <= WidgetSnapshot.maximumEncodedBytes else {
            throw Error.encodedSizeExceedsLimit
        }
        return snapshot
    }

    private func orderedProviders(in state: ControlState) -> [ProviderSummary] {
        let configuredOrder = if let settingsOrder = state.settings?.providerOrder,
                                 settingsOrder.isEmpty == false {
            settingsOrder
        } else if state.bridge.configuredProviderIds.isEmpty == false {
            state.bridge.configuredProviderIds
        } else {
            state.providers.map(\.id)
        }
        let providersById = Dictionary(
            state.providers.reversed().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<String>()
        let configured = configuredOrder.compactMap { id -> ProviderSummary? in
            guard seen.insert(id).inserted else { return nil }
            return providersById[id]
        }
        let remaining = state.providers.filter { seen.insert($0.id).inserted }
        return configured + remaining
    }

    private func makeWindowSnapshot(_ window: ProviderWindow) -> WidgetWindowSnapshot {
        WidgetWindowSnapshot(
            kind: window.kind,
            label: window.label,
            usedPercent: window.usedPercent.flatMap { (0...100).contains($0) ? $0 : nil },
            resetAtEpoch: window.resetAtEpoch
        )
    }

    private func history(
        for provider: ProviderSummary,
        summary: WidgetHistorySummary?
    ) -> [WidgetHistoryDay] {
        guard let summary else { return [] }

        let availableKinds = Set(
            summary.days.lazy
                .filter { $0.providerId == provider.id }
                .map(\.windowKind)
        )
        var seenKinds = Set<String>()
        let selectedKinds = provider.windows
            .prefix(WidgetSnapshot.maximumWindowCountPerProvider)
            .compactMap { window -> String? in
                guard availableKinds.contains(window.kind), seenKinds.insert(window.kind).inserted else {
                    return nil
                }
                return window.kind
            }
            .prefix(WidgetSnapshot.maximumHistoryWindowCountPerProvider)
        let kindOrder = Dictionary(uniqueKeysWithValues: selectedKinds.enumerated().map { ($1, $0) })

        let recentDayEpochs = Set(
            summary.days.lazy
                .filter { $0.providerId == provider.id && kindOrder[$0.windowKind] != nil }
                .map(\.dayStartEpoch)
                .sorted(by: >)
                .reduce(into: [Int]()) { result, epoch in
                    if result.last != epoch {
                        result.append(epoch)
                    }
                }
                .prefix(WidgetSnapshot.maximumHistoryDayCount)
        )

        return summary.days
            .filter {
                $0.providerId == provider.id
                    && kindOrder[$0.windowKind] != nil
                    && recentDayEpochs.contains($0.dayStartEpoch)
            }
            .sorted {
                if $0.dayStartEpoch != $1.dayStartEpoch {
                    return $0.dayStartEpoch < $1.dayStartEpoch
                }
                let leftKind = kindOrder[$0.windowKind] ?? .max
                let rightKind = kindOrder[$1.windowKind] ?? .max
                if leftKind != rightKind { return leftKind < rightKind }
                return $0.windowKind < $1.windowKind
            }
    }

    private func historyStartEpoch(
        providerIds: [String],
        summaries: [String: WidgetHistorySummary]
    ) -> Int? {
        providerIds.compactMap { summaries[$0]?.historyStartEpoch }.min()
    }

    private func generationEpoch(state: ControlState) -> Int {
        let providerEpochs = state.providers.compactMap(\.updatedAtEpoch)
        return ([state.bridge.lastProviderRefreshEpoch].compactMap { $0 } + providerEpochs).max() ?? 0
    }
}
