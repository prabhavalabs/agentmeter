import AgentMeterCore
import AppKit
import SwiftUI

public struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.state.connection.selectedDeviceName ?? "AgentMeter")
                    .font(.headline)
                Label(
                    model.state.connection.phase.displayName,
                    systemImage: model.state.connection.phase.symbolName
                )
                .foregroundStyle(model.state.connection.phase.tint)
                .font(.caption)
            }

            if model.state.providers.isEmpty == false {
                Divider()
                ForEach(model.state.providers.prefix(4)) { provider in
                    HStack {
                        ProviderMark(providerId: provider.id, name: provider.name, size: 24)
                        Text(provider.name)
                        Spacer()
                        Text(UsageFormatting.percentage(provider.windows.first?.usedPercent))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Divider()
            Button("Open AgentMeter") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .keyboardShortcut("o")

            if model.state.connection.phase == .connected {
                Button("Disconnect") { Task { await model.disconnect() } }
            } else {
                Button("Reconnect") { Task { await model.reconnect() } }
            }
            Button("Refresh Usage") { Task { await model.refreshProviders() } }
            Divider()
            SettingsLink { Text("Settings…") }
            Button("Quit AgentMeter") {
                Task {
                    await model.stop()
                    NSApplication.shared.terminate(nil)
                }
            }
            .keyboardShortcut("q")
        }
        .padding(8)
        .frame(width: 260)
        .task { await model.start() }
    }
}
