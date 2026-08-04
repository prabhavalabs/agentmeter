import AgentMeterCore

public struct MenuProviderExpansion: Equatable, Sendable {
    public private(set) var expandedProviderIDs: Set<String>

    public init(expandedProviderIDs: Set<String> = []) {
        self.expandedProviderIDs = expandedProviderIDs
    }

    public func contains(_ providerID: String) -> Bool {
        expandedProviderIDs.contains(providerID)
    }

    public mutating func toggle(_ providerID: String) {
        if expandedProviderIDs.contains(providerID) {
            expandedProviderIDs.remove(providerID)
        } else {
            expandedProviderIDs.insert(providerID)
        }
    }
}

public struct MenuProviderDetails: Equatable, Sendable {
    public let sessionWindow: ProviderWindow?
    public let cycleWindow: ProviderWindow?
    public let modelWindows: [ProviderWindow]

    public init(provider: ProviderSummary) {
        let usesQuotaSections = provider.id == "claude" || provider.id == "codex"
        sessionWindow = usesQuotaSections
            ? provider.windows.first {
                $0.kind == "session"
                    && $0.label.localizedCaseInsensitiveContains("session")
            }
            : nil
        cycleWindow = usesQuotaSections
            ? provider.windows.first { $0.kind == "weekly" }
            : nil
        let excluded = Set([sessionWindow?.id, cycleWindow?.id].compactMap { $0 })
        modelWindows = provider.windows.filter { excluded.contains($0.id) == false }
    }
}
