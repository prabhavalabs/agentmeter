import AgentMeterCore
import AppKit
import SwiftUI

public struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(LaunchAtLoginController.self) private var launchAtLogin
    @Environment(BridgeServiceController.self) private var bridgeService
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
                Label(bridgeService.state.title, systemImage: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(.secondary)
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
            Toggle("Launch at Login", isOn: launchAtLoginBinding)
                .disabled(launchAtLogin.isUpdating)
            Divider()
            SettingsLink { Text("Settings…") }
            Button("Quit AgentMeter") {
                Task {
                    await model.stop()
                    await bridgeService.stop()
                    NSApplication.shared.terminate(nil)
                }
            }
            .keyboardShortcut("q")
        }
        .padding(8)
        .frame(width: 260)
        .task {
            await bridgeService.start()
            await model.start()
            if model.bridgeReachable { bridgeService.confirmBridgeReady() }
        }
        .onAppear { launchAtLogin.refresh() }
        .onChange(of: model.bridgeReachable) { _, reachable in
            if reachable { bridgeService.confirmBridgeReady() }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { enabled in
                Task {
                    let saved = await launchAtLogin.setEnabled(enabled)
                    if saved { model.preferences.launchAtLogin = enabled }
                }
            }
        )
    }
}
