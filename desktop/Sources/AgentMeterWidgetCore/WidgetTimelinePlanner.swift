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
    public static func plan(snapshot: WidgetSnapshot, nowEpoch: Int) -> WidgetTimelinePlan {
        let (candidateCeiling, overflow) = nowEpoch.addingReportingOverflow(86_400)
        let ceiling = overflow ? Int.max : candidateCeiling
        var checkpoints = Set<Int>()

        if let reset = snapshot.providers
            .lazy
            .flatMap(\.windows)
            .compactMap(\.resetAtEpoch)
            .filter({ $0 > nowEpoch && $0 <= ceiling })
            .min() {
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
}
