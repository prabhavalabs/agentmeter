import AgentMeterWidgetCore
import AppIntents
import Foundation

typealias WidgetSnapshotLoader = @Sendable () throws -> WidgetSnapshot?

struct ProviderEntity: AppEntity, Equatable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")
    static let defaultQuery = ProviderEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct WindowEntity: AppEntity, Equatable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Usage Window")
    static let defaultQuery = WindowEntityQuery()

    let providerID: String
    let windowKind: String
    let label: String

    var id: String { "\(providerID):\(windowKind)" }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label)")
    }
}

struct ProviderEntityQuery: EntityQuery {
    private let loader: WidgetSnapshotLoader

    init() {
        loader = WidgetEntitySnapshotSource.load
    }

    init(loader: @escaping WidgetSnapshotLoader) {
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
        var seen = Set<String>()
        return snapshot.providers.compactMap { provider in
            guard seen.insert(provider.id).inserted else { return nil }
            return ProviderEntity(id: provider.id, name: provider.name)
        }
    }
}

struct WindowEntityQuery: EntityQuery {
    @IntentParameterDependency<FocusWidgetIntent>(\.$provider)
    private var intent

    private let loader: WidgetSnapshotLoader
    private let selectedProviderID: String?

    init() {
        loader = WidgetEntitySnapshotSource.load
        selectedProviderID = nil
    }

    init(
        loader: @escaping WidgetSnapshotLoader,
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
        guard let providerID = selectedProviderID ?? intent?.provider.id else { return [] }
        return allEntities().filter { $0.providerID == providerID }
    }

    private func allEntities() -> [WindowEntity] {
        guard let snapshot = try? loader() else { return [] }
        var seen = Set<String>()
        return snapshot.providers.flatMap { provider in
            provider.windows.compactMap { window in
                let entity = WindowEntity(
                    providerID: provider.id,
                    windowKind: window.kind,
                    label: window.label
                )
                guard seen.insert(entity.id).inserted else { return nil }
                return entity
            }
        }
    }
}

private enum WidgetEntitySnapshotSource {
    static let appGroupIdentifier = "group.com.prabhavalabs.agentmeter.shared"

    static func load() throws -> WidgetSnapshot? {
        guard let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }
        return try WidgetSnapshotStore(directoryURL: directory).load()
    }
}
