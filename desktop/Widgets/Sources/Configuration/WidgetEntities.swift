import AgentMeterWidgetCore
import AppIntents
import Foundation

typealias WidgetEntitySnapshotLoader = @Sendable () throws -> WidgetSnapshot?

struct ProviderEntity: AppEntity, Equatable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")
    static let defaultQuery = ProviderEntityQuery()

    let id: String
    let name: String
    var usageSummary: String?

    var displayRepresentation: DisplayRepresentation {
        guard let usageSummary else {
            return DisplayRepresentation(title: "\(name)")
        }
        return DisplayRepresentation(title: "\(name)", subtitle: "\(usageSummary)")
    }
}

struct WindowEntity: AppEntity, Equatable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Usage Window")
    static let defaultQuery = WindowEntityQuery()

    let providerID: String
    let windowKind: String
    let label: String
    var detail: String?

    var id: String { "\(providerID):\(windowKind)" }

    var displayRepresentation: DisplayRepresentation {
        guard let detail else {
            return DisplayRepresentation(title: "\(label)")
        }
        return DisplayRepresentation(title: "\(label)", subtitle: "\(detail)")
    }
}

enum WidgetEntityUsageText {
    static func percentText(_ usedPercent: Int?) -> String {
        usedPercent.map { "\($0)% used" } ?? "Not reported"
    }

    static func providerSummary(_ provider: WidgetProviderSnapshot) -> String? {
        guard let window = provider.windows.first else { return nil }
        return "\(window.label) · \(percentText(window.usedPercent))"
    }
}

struct ProviderEntityQuery: EntityQuery {
    private let loader: WidgetEntitySnapshotLoader

    init() {
        loader = WidgetEntitySnapshotSource.load
    }

    init(loader: @escaping WidgetEntitySnapshotLoader) {
        self.loader = loader
    }

    func entities(for identifiers: [ProviderEntity.ID]) async throws -> [ProviderEntity] {
        let requested = Set(identifiers)
        return allEntities().filter { requested.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ProviderEntity] {
        allEntities()
    }

    private func allEntities() -> [ProviderEntity] {
        guard let snapshot = try? loader() else { return [] }
        let validProviders = snapshot.providers.filter {
            AgentMeterRoute.isValidProviderID($0.id)
        }
        let identityCounts = validProviders.reduce(into: [String: Int]()) {
            $0[$1.id, default: 0] += 1
        }
        return validProviders.compactMap { provider in
            guard identityCounts[provider.id] == 1 else { return nil }
            return ProviderEntity(
                id: provider.id,
                name: provider.name,
                usageSummary: WidgetEntityUsageText.providerSummary(provider)
            )
        }
    }
}

struct WindowEntityQuery: EntityQuery {
    @IntentParameterDependency<FocusWidgetIntent>(\.$provider)
    private var intent

    private let loader: WidgetEntitySnapshotLoader
    private let selectedProviderID: String?

    init() {
        loader = WidgetEntitySnapshotSource.load
        selectedProviderID = nil
    }

    init(
        loader: @escaping WidgetEntitySnapshotLoader,
        selectedProviderID: String? = nil
    ) {
        self.loader = loader
        self.selectedProviderID = selectedProviderID
    }

    func entities(for identifiers: [WindowEntity.ID]) async throws -> [WindowEntity] {
        let requested = Set(identifiers)
        return allEntities().filter { requested.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WindowEntity] {
        let all = allEntities()
        // An empty suggestion list renders as a dead popover in the system
        // sheet, so before an agent is chosen the picker offers every window,
        // subtitled with its agent for disambiguation.
        guard let providerID = selectedProviderID ?? intent?.provider.id else { return all }
        let scoped = all.filter { $0.providerID == providerID }
        return scoped.isEmpty ? all : scoped
    }

    private func allEntities() -> [WindowEntity] {
        guard let snapshot = try? loader() else { return [] }
        let candidates = snapshot.providers.flatMap { provider -> [WindowEntity] in
            guard AgentMeterRoute.isValidProviderID(provider.id) else { return [] }
            return provider.windows.compactMap { window in
                guard window.kind.isEmpty == false, window.kind.contains(":") == false else {
                    return nil
                }
                let entity = WindowEntity(
                    providerID: provider.id,
                    windowKind: window.kind,
                    label: window.label,
                    detail: "\(provider.name) · "
                        + WidgetEntityUsageText.percentText(window.usedPercent)
                )
                return entity
            }
        }
        let identityCounts = candidates.reduce(into: [String: Int]()) {
            $0[$1.id, default: 0] += 1
        }
        return candidates.filter { identityCounts[$0.id] == 1 }
    }
}

private enum WidgetEntitySnapshotSource {
    // Single source of truth for the container — a duplicated literal here once
    // left the configuration pickers reading a nonexistent group.
    static func load() throws -> WidgetSnapshot? {
        guard let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetSnapshotLoader.appGroupIdentifier
        ) else {
            return nil
        }
        return try WidgetSnapshotStore(directoryURL: directory).load()
    }
}
