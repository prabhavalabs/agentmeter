import AgentMeterCore
import SwiftUI

public struct AgentsView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Coding agents").font(.largeTitle.bold())
                        Text("Choose what appears on AgentMeter and review collection health.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await model.refreshProviders() }
                    } label: {
                        if model.activeOperations.contains(.providerRefresh) {
                            HStack(spacing: 7) {
                                ProgressView().controlSize(.small)
                                Text("Refreshing…")
                            }
                        } else {
                            Label("Refresh Usage", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.activeOperations.contains(.providerRefresh))
                }

                providerList

                if model.state.settings == nil {
                    Label(
                        requiresManagementFirmware
                            ? "The connected device uses legacy firmware. Connect it by USB-C and install the current firmware once to enable Show controls and two-way sync."
                            : "Connect an AgentMeter to change what is shown on the display.",
                        systemImage: requiresManagementFirmware
                            ? "externaldrive.badge.exclamationmark"
                            : "display.trianglebadge.exclamationmark"
                    )
                    .font(.callout)
                    .foregroundStyle(requiresManagementFirmware ? AgentMeterTheme.warning : .secondary)
                }

                if model.state.providers.contains(where: {
                    $0.status == "unavailable" || $0.status == "error"
                }) {
                    providerSetupHelp
                }

                privacyNote
            }
            .padding(28)
        }
        .navigationTitle("Agents")
    }

    private var providerList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agent").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("Collect").font(.caption.bold()).foregroundStyle(.secondary).frame(width: 58)
                Text("Show").font(.caption.bold()).foregroundStyle(.secondary).frame(width: 58)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            Divider()
            ForEach(Array(providerCatalog.enumerated()), id: \.element.id) { index, provider in
                providerRow(provider, index: index)
                if index < providerCatalog.count - 1 { Divider().padding(.leading, 68) }
            }
        }
        .agentMeterCard(emphasized: true)
    }

    private func providerRow(_ provider: CatalogProvider, index: Int) -> some View {
        HStack(spacing: 14) {
            ProviderMark(providerId: provider.id, name: provider.name, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(provider.name).font(.headline)
                    statusPill(provider.id)
                }
                Text(providerDescription(provider.id))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Button {
                    moveProvider(at: index, by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(index == 0 || model.activeOperations.contains(.settings))
                .help("Move up")
                Button {
                    moveProvider(at: index, by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(index == providerCatalog.count - 1 || model.activeOperations.contains(.settings))
                .help("Move down")
            }
            Toggle("Collected", isOn: collectionBinding(provider.id))
                .toggleStyle(.switch)
                .labelsHidden()
                .frame(width: 58)
                .disabled(
                    model.activeOperations.contains(.providerRefresh)
                        || isLastCollectedProvider(provider.id)
                )
                .accessibilityLabel("Collect \(provider.name) usage")
            Toggle("Shown", isOn: visibilityBinding(provider.id))
                .toggleStyle(.switch)
                .labelsHidden()
                .frame(width: 58)
                .disabled(
                    model.state.settings == nil
                        || model.activeOperations.contains(.settings)
                        || isLastVisibleProvider(provider.id)
                )
                .accessibilityLabel("Show \(provider.name) on AgentMeter")
                .help(showControlHelp)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func statusPill(_ id: String) -> some View {
        if model.state.bridge.configuredProviderIds.contains(id) == false {
            StatusPill("Disabled", symbol: "pause.circle", tint: AgentMeterTheme.secondaryText)
        } else {
            let status = model.state.providers.first(where: { $0.id == id })?.status
            switch status {
            case "ok":
                StatusPill("Live", symbol: "waveform.path.ecg", tint: AgentMeterTheme.success)
            case "stale":
                StatusPill("Stale", symbol: "clock.badge.exclamationmark", tint: AgentMeterTheme.warning)
            case "unavailable":
                StatusPill("Unavailable", symbol: "exclamationmark.circle", tint: AgentMeterTheme.warning)
            case "error":
                StatusPill("Needs attention", symbol: "exclamationmark.triangle", tint: AgentMeterTheme.warning)
            default:
                StatusPill("Not detected", symbol: "minus.circle", tint: AgentMeterTheme.secondaryText)
            }
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .foregroundStyle(AgentMeterTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Credentials stay with your tools").font(.headline)
                Text("AgentMeter reads normalized usage from the local bridge. It does not ask for or store provider credentials, prompts, or source code.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .agentMeterCard()
    }

    private var providerSetupHelp: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(AgentMeterTheme.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text("A provider needs attention").font(.headline)
                Text("Sign in or verify the provider in CodexBar, then refresh usage here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Link(
                "Setup Help",
                destination: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/cli.md")!
            )
        }
        .padding(18)
        .agentMeterCard()
    }

    private var providerCatalog: [CatalogProvider] {
        let known = [
            CatalogProvider(id: "codex", name: "Codex"),
            CatalogProvider(id: "claude", name: "Claude"),
            CatalogProvider(id: "gemini", name: "Gemini"),
            CatalogProvider(id: "cursor", name: "Cursor"),
        ]
        let byId = Dictionary(uniqueKeysWithValues: known.map { ($0.id, $0) })
        let configured = model.state.settings?.providerOrder ?? known.map(\.id)
        let extras = model.state.providers
            .filter { byId[$0.id] == nil }
            .map { CatalogProvider(id: $0.id, name: $0.name) }
        var output = configured.compactMap { id in
            byId[id] ?? extras.first(where: { $0.id == id })
        }
        for provider in known + extras where output.contains(where: { $0.id == provider.id }) == false {
            output.append(provider)
        }
        return output
    }

    private func visibilityBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { model.state.settings?.hiddenProviderIds.contains(id) == false },
            set: { visible in
                guard let settings = model.state.settings else { return }
                var hidden = Set(settings.hiddenProviderIds)
                if visible { hidden.remove(id) } else { hidden.insert(id) }
                var patch = DeviceSettingsPatch(baseRevision: settings.revision)
                patch.hiddenProviderIds = hidden.sorted()
                Task { await model.patchSettings(patch) }
            }
        )
    }

    private func collectionBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { model.state.bridge.configuredProviderIds.contains(id) },
            set: { enabled in
                var ids = model.state.bridge.configuredProviderIds
                if enabled {
                    if ids.contains(id) == false { ids.append(id) }
                } else {
                    ids.removeAll { $0 == id }
                }
                guard ids.isEmpty == false else { return }
                Task {
                    await model.updateProviderCollection(
                        ids: ids,
                        pollIntervalSeconds: model.state.bridge.pollIntervalSeconds
                    )
                }
            }
        )
    }

    private func isLastCollectedProvider(_ id: String) -> Bool {
        let configured = model.state.bridge.configuredProviderIds
        return configured.count == 1 && configured.first == id
    }

    private func isLastVisibleProvider(_ id: String) -> Bool {
        guard let settings = model.state.settings,
              settings.hiddenProviderIds.contains(id) == false else { return false }
        return providerCatalog.filter { settings.hiddenProviderIds.contains($0.id) == false }.count == 1
    }

    private var requiresManagementFirmware: Bool {
        model.state.connection.phase == .connected
            && model.state.connection.managementAvailable == false
    }

    private var showControlHelp: String {
        if requiresManagementFirmware {
            return "Install the current AgentMeter firmware by USB-C to enable two-way display settings."
        }
        if model.state.settings == nil {
            return "Connect AgentMeter to change this setting."
        }
        return "Choose whether this agent appears on AgentMeter."
    }

    private func moveProvider(at index: Int, by delta: Int) {
        let destination = index + delta
        guard providerCatalog.indices.contains(destination) else { return }
        var order = providerCatalog.map(\.id)
        order.swapAt(index, destination)
        Task {
            await model.setProviderOrder(order)
        }
    }

    private func providerDescription(_ id: String) -> String {
        if model.state.bridge.configuredProviderIds.contains(id) == false {
            return "Collection is disabled on this Mac"
        }
        guard let provider = model.state.providers.first(where: { $0.id == id }) else {
            return "No local usage source detected"
        }
        return UsageFormatting.updatedAge(
            updatedAtEpoch: provider.updatedAtEpoch,
            nowEpoch: Int(Date().timeIntervalSince1970)
        )
    }
}

private struct CatalogProvider: Identifiable, Equatable {
    let id: String
    let name: String
}
