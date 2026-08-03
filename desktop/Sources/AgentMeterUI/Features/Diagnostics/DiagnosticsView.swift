import AgentMeterCore
import AppKit
import SwiftUI

public struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingRestart = false
    @State private var confirmingHistoryClear = false
    @State private var copied = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Diagnostics").font(.largeTitle.bold())
                        Text("Sanitized status for troubleshooting this Mac and AgentMeter.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(copied ? "Copied" : "Copy Diagnostics", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        copyDiagnostics()
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(alignment: .top, spacing: 16) {
                    diagnosticGroup("Software", rows: softwareRows)
                    diagnosticGroup("Connection", rows: connectionRows)
                }

                providerHealth
                recentEvents
                actionCard
                privacyCard
            }
            .padding(28)
        }
        .navigationTitle("Diagnostics")
        .confirmationDialog("Restart the AgentMeter bridge?", isPresented: $confirmingRestart) {
            Button("Restart Bridge") { Task { await model.restartBridge() } }
        } message: {
            Text("Usage collection and Bluetooth synchronization pause briefly, then resume automatically.")
        }
        .confirmationDialog("Clear local usage history?", isPresented: $confirmingHistoryClear) {
            Button("Clear History", role: .destructive) { Task { await model.clearHistory() } }
        } message: {
            Text("Current provider usage and device settings are not removed.")
        }
        .task { await model.refreshDiagnostics() }
    }

    private func diagnosticGroup(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).padding(16)
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1).font(.body.monospaced()).textSelection(.enabled)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                if index < rows.count - 1 { Divider().padding(.leading, 16) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .agentMeterCard()
    }

    private var providerHealth: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Provider health").font(.headline).padding(16)
            Divider()
            if model.state.bridge.providerHealth.isEmpty {
                Text("No provider health data is available.")
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ForEach(model.state.bridge.providerHealth.keys.sorted(), id: \.self) { id in
                    HStack {
                        ProviderMark(providerId: id, name: providerName(id), size: 28)
                        Text(providerName(id))
                        Spacer()
                        healthStatus(model.state.bridge.providerHealth[id] ?? "unknown")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        .agentMeterCard()
    }

    private var actionCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Maintenance").font(.headline)
                Text("These actions do not update or replace device firmware.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh Device", systemImage: "arrow.clockwise") {
                Task { await model.refreshDevice() }
            }
            Button("Clear History…", role: .destructive) { confirmingHistoryClear = true }
            Button("Restart Bridge…") { confirmingRestart = true }
        }
        .padding(18)
        .agentMeterCard()
    }

    private var recentEvents: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent events").font(.headline)
                Spacer()
                Text("Sanitized · last \(model.diagnostics?.recentEvents.count ?? 0)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()
            if let events = model.diagnostics?.recentEvents, events.isEmpty == false {
                ForEach(events.suffix(12).reversed()) { event in
                    HStack(spacing: 12) {
                        Image(systemName: eventSymbol(event.type))
                            .foregroundStyle(AgentMeterTheme.accent)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(eventTitle(event.type))
                            Text(Date(timeIntervalSince1970: Double(event.occurredAtEpoch)), style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("r\(event.revision)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                }
            } else {
                Text("No recent bridge events are available.")
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
        }
        .agentMeterCard()
    }

    private var privacyCard: some View {
        Label {
            Text("Diagnostics exclude credentials, prompts, source code, account identity, and raw provider responses.")
        } icon: {
            Image(systemName: "hand.raised.fill").foregroundStyle(AgentMeterTheme.success)
        }
        .font(.callout)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .agentMeterCard()
    }

    private var softwareRows: [(String, String)] {
        [
            ("App", "0.1.0"),
            ("Bridge", model.state.bridge.version),
            ("Firmware", model.state.information?.firmwareVersion ?? "Unavailable"),
            ("IPC schema", model.diagnostics.map { String($0.ipcSchemaVersion) } ?? "1"),
            ("Snapshot schema", model.state.information.map { String($0.snapshotSchemaVersion) } ?? "Unavailable"),
            ("Management schema", model.state.information.map { String($0.managementSchemaVersion) } ?? "Unavailable"),
        ]
    }

    private var connectionRows: [(String, String)] {
        [
            ("Bridge", model.bridgeReachable ? "Reachable" : "Unavailable"),
            ("Bluetooth", model.state.connection.phase.displayName),
            ("Management", managementDescription),
            ("Signal", model.state.connection.rssi.map { "\($0) dBm" } ?? "Unavailable"),
            ("State revision", String(model.state.revision)),
            ("Settings revision", model.state.settings.map { String($0.revision) } ?? "Unavailable"),
        ]
    }

    private var managementDescription: String {
        switch model.state.connection.managementAvailable {
        case true: "Available"
        case false: "Legacy device"
        case nil: "Unavailable"
        }
    }

    @ViewBuilder
    private func healthStatus(_ status: String) -> some View {
        switch status {
        case "ok": StatusPill("Healthy", symbol: "checkmark.circle.fill", tint: AgentMeterTheme.success)
        case "stale": StatusPill("Stale", symbol: "clock", tint: AgentMeterTheme.warning)
        default: StatusPill(status.capitalized, symbol: "exclamationmark.circle", tint: AgentMeterTheme.warning)
        }
    }

    private func providerName(_ id: String) -> String {
        model.state.providers.first(where: { $0.id == id })?.name ?? id.capitalized
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsText, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private func eventTitle(_ type: String) -> String {
        type.replacingOccurrences(of: ".", with: " ").capitalized
    }

    private func eventSymbol(_ type: String) -> String {
        if type.hasPrefix("connection") { return "antenna.radiowaves.left.and.right" }
        if type.hasPrefix("providers") { return "sparkles" }
        if type.hasPrefix("settings") { return "slider.horizontal.3" }
        if type.hasPrefix("device") { return "display" }
        return "waveform.path.ecg"
    }

    private var diagnosticsText: String {
        let software = softwareRows.map { "\($0.0): \($0.1)" }
        let connection = connectionRows.map { "\($0.0): \($0.1)" }
        let providers = model.state.bridge.providerHealth.keys.sorted().map {
            "Provider \($0): \(model.state.bridge.providerHealth[$0] ?? "unknown")"
        }
        let events = model.diagnostics?.recentEvents.suffix(12).map {
            "Event \($0.type): revision \($0.revision), epoch \($0.occurredAtEpoch)"
        } ?? []
        return (["AgentMeter diagnostics"] + software + connection + providers + events)
            .joined(separator: "\n")
    }
}
