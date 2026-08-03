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
                    Button("Refresh Usage", systemImage: "arrow.clockwise") {
                        Task { await model.refreshProviders() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.activeOperations.contains(.providerRefresh))
                }

                if model.state.settings == nil {
                    ContentUnavailableView(
                        "Display controls unavailable",
                        systemImage: "display.trianglebadge.exclamationmark",
                        description: Text("Connect a management-capable AgentMeter to change agent visibility.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .agentMeterCard()
                } else {
                    providerList
                }

                privacyNote
            }
            .padding(28)
        }
        .navigationTitle("Agents")
    }

    private var providerList: some View {
        VStack(spacing: 0) {
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
            Toggle("Shown", isOn: visibilityBinding(provider.id))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(model.activeOperations.contains(.settings))
                .accessibilityLabel("Show \(provider.name) on AgentMeter")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func statusPill(_ id: String) -> some View {
        let status = model.state.providers.first(where: { $0.id == id })?.status
        switch status {
        case "ok":
            StatusPill("Live", symbol: "waveform.path.ecg", tint: AgentMeterTheme.success)
        case "stale":
            StatusPill("Stale", symbol: "clock.badge.exclamationmark", tint: AgentMeterTheme.warning)
        case "unavailable":
            StatusPill("Unavailable", symbol: "exclamationmark.circle", tint: AgentMeterTheme.warning)
        default:
            StatusPill("Not detected", symbol: "minus.circle", tint: AgentMeterTheme.secondaryText)
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
