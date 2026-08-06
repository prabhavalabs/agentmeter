public struct WidgetTimelinePlan: Equatable, Sendable {
    public let currentEpoch: Int
    public let checkpoints: [Int]
    public let reloadAfterEpoch: Int

    public init(currentEpoch: Int, checkpoints: [Int], reloadAfterEpoch: Int) {
        self.currentEpoch = currentEpoch
        self.checkpoints = checkpoints
        self.reloadAfterEpoch = reloadAfterEpoch
    }
}

public enum FocusWindowCapacity {
    public static func additionalLimit(for family: WidgetFamily) -> Int {
        switch family {
        case .small: 0
        case .medium, .large: 2
        case .extraLarge: 4
        }
    }
}

public enum WidgetTimelinePlanner {
    public static func plan(
        snapshot: WidgetSnapshot,
        configuration: WidgetRenderConfiguration,
        family: WidgetFamily,
        nowEpoch: Int
    ) -> WidgetTimelinePlan {
        let (candidateCeiling, overflow) = nowEpoch.addingReportingOverflow(86_400)
        let ceiling = overflow ? Int.max : candidateCeiling
        var checkpoints = Set<Int>()

        for reset in renderedResetEpochs(
            snapshot: snapshot,
            configuration: configuration,
            family: family,
            nowEpoch: nowEpoch
        ) where reset > nowEpoch && reset <= ceiling {
            checkpoints.insert(reset)
        }

        let staleEpoch = WidgetPresentationResolver.staleEpoch(for: snapshot)
        if staleEpoch > nowEpoch, staleEpoch <= ceiling {
            checkpoints.insert(staleEpoch)
        }
        if ceiling > nowEpoch {
            checkpoints.insert(ceiling)
        }

        return WidgetTimelinePlan(
            currentEpoch: nowEpoch,
            checkpoints: checkpoints.sorted(),
            reloadAfterEpoch: ceiling
        )
    }

    private static func renderedResetEpochs(
        snapshot: WidgetSnapshot,
        configuration: WidgetRenderConfiguration,
        family: WidgetFamily,
        nowEpoch: Int
    ) -> [Int] {
        if configuration.kind == .focus,
           let focusProviderID = configuration.focusProviderID,
           snapshot.providers.contains(where: { $0.id == focusProviderID }) == false {
            return []
        }
        let presentation = WidgetPresentationResolver.resolve(
            configuration: configuration,
            snapshot: snapshot,
            family: family,
            nowEpoch: nowEpoch
        )
        let limits = renderedWindowLimits(configuration: configuration, family: family)
        return presentation.providers.flatMap { provider in
            let windows: [WidgetRingPresentation] = Array(
                provider.rings.prefix(limits.rings)
            ) + Array(provider.additionalWindows.prefix(limits.additional))
            return windows.compactMap { ring -> Int? in
                guard case let .scheduled(epoch) = ring.resetState else { return nil }
                return epoch
            }
        }
    }

    private static func renderedWindowLimits(
        configuration: WidgetRenderConfiguration,
        family: WidgetFamily
    ) -> (rings: Int, additional: Int) {
        switch configuration.kind {
        case .focus:
            return (2, FocusWindowCapacity.additionalLimit(for: family))
        case .dashboard:
            let rings = configuration.layout == .compact || family == .small ? 1 : 2
            let additional = family == .extraLarge && configuration.layout != .compact ? 2 : 0
            return (rings, additional)
        }
    }
}
