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
        return presentation.providers.flatMap { provider in
            (provider.rings + provider.additionalWindows).compactMap { ring in
                guard case let .scheduled(epoch) = ring.resetState else { return nil }
                return epoch
            }
        }
    }
}
