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
        VStack(alignment: .leading, spacing: 10) {
            deviceHeader

            if model.state.providers.isEmpty == false {
                menuSection("Live usage") {
                    VStack(spacing: 0) {
                        ForEach(Array(model.state.providers.prefix(4).enumerated()), id: \.element.id) {
                            index, provider in
                            providerRow(provider)
                            if index < min(model.state.providers.count, 4) - 1 {
                                menuDivider
                            }
                        }
                    }
                }
            }

            menuSection("Open AgentMeter") {
                VStack(spacing: 0) {
                    navigationRow(.overview)
                    menuDivider
                    navigationRow(.device)
                    menuDivider
                    navigationRow(.agents)
                    menuDivider
                    navigationRow(.display)
                }
            }

            menuSection("Controls") {
                VStack(spacing: 0) {
                    connectionRow
                    menuDivider
                    refreshRow
                    menuDivider
                    launchAtLoginRow
                }
            }

            VStack(spacing: 0) {
                SettingsLink {
                    MenuBarRowLabel(
                        title: "Preferences",
                        symbol: "gearshape",
                        tint: AgentMeterTheme.accent,
                        trailingSymbol: "chevron.right"
                    )
                }
                .buttonStyle(.plain)

                menuDivider

                Button {
                    Task {
                        await model.stop()
                        await bridgeService.stop()
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    MenuBarRowLabel(
                        title: "Quit AgentMeter",
                        symbol: "xmark",
                        tint: AgentMeterTheme.critical,
                        isDestructive: true
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
            }
            .menuBarGroup()
        }
        .padding(10)
        .frame(width: 320)
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

    private var deviceHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(model.state.connection.phase.tint.opacity(0.14))
                Image(systemName: model.state.connection.phase.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(model.state.connection.phase.tint)
            }
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.state.connection.selectedDeviceName ?? "AgentMeter")
                    .font(.headline)
                    .lineLimit(1)

                Label(
                    model.state.connection.phase.displayName,
                    systemImage: model.state.connection.phase.symbolName
                )
                .foregroundStyle(model.state.connection.phase.tint)
                .font(.caption.weight(.semibold))

                Label(
                    bridgeService.state.title,
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                .foregroundStyle(.secondary)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .menuBarGroup()
        .accessibilityElement(children: .combine)
    }

    private func providerRow(_ provider: ProviderSummary) -> some View {
        HStack(spacing: 10) {
            ProviderMark(providerId: provider.id, name: provider.name, size: 30)
            Text(provider.name)
                .font(.body.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(UsageFormatting.percentage(provider.windows.first?.usedPercent))
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .accessibilityElement(children: .combine)
    }

    private func navigationRow(_ section: NavigationSection) -> some View {
        Button {
            openMainWindow(section: section)
        } label: {
            MenuBarRowLabel(
                title: section.menuTitle,
                symbol: section.symbolName,
                tint: section.menuTint,
                trailingSymbol: "chevron.right"
            )
        }
        .buttonStyle(.plain)
        .help("Open " + section.menuTitle)
    }

    @ViewBuilder
    private var connectionRow: some View {
        let connected = model.state.connection.phase == .connected
        Button {
            Task {
                if connected {
                    await model.disconnect()
                } else {
                    await model.reconnect()
                }
            }
        } label: {
            MenuBarRowLabel(
                title: connected ? "Disconnect device" : "Reconnect device",
                symbol: connected
                    ? "antenna.radiowaves.left.and.right.slash"
                    : "antenna.radiowaves.left.and.right",
                tint: connected ? AgentMeterTheme.warning : AgentMeterTheme.accent
            ) {
                if model.activeOperations.contains(.deviceConnection) {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.activeOperations.contains(.deviceConnection))
    }

    private var refreshRow: some View {
        Button {
            Task { await model.refreshProviders() }
        } label: {
            MenuBarRowLabel(
                title: "Refresh usage",
                symbol: "arrow.clockwise",
                tint: AgentMeterTheme.accent
            ) {
                if model.activeOperations.contains(.providerRefresh) {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.activeOperations.contains(.providerRefresh))
    }

    @ViewBuilder
    private var launchAtLoginRow: some View {
        if bridgeService.isCommunityBuild {
            Button {
                bridgeService.openLoginItemsSettings()
            } label: {
                MenuBarRowLabel(
                    title: "Launch at Login",
                    symbol: "power",
                    tint: AgentMeterTheme.accent,
                    trailingSymbol: "arrow.up.forward.app"
                )
            }
            .buttonStyle(.plain)
            .help("Open Login Items in System Settings")
        } else {
            MenuBarToggleRow(
                title: "Launch at Login",
                symbol: "power",
                tint: AgentMeterTheme.accent,
                isOn: launchAtLoginBinding
            )
            .disabled(launchAtLogin.isUpdating)
        }
    }

    private var menuDivider: some View {
        Divider()
            .padding(.leading, 48)
    }

    private func menuSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.6)
                .padding(.leading, 4)
            content()
                .menuBarGroup()
        }
    }

    private func openMainWindow(section: NavigationSection) {
        model.selectedSection = section
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "main")
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

extension NavigationSection {
    var menuTitle: String {
        switch self {
        case .overview: "Overview"
        case .device: "Device & Bluetooth"
        case .agents: "Coding Agents"
        case .display: "Display Settings"
        case .diagnostics: "Diagnostics"
        }
    }

    var menuTint: Color {
        switch self {
        case .overview: AgentMeterTheme.accent
        case .device: Color(red: 0.42, green: 0.72, blue: 1.0)
        case .agents: Color(red: 0.36, green: 0.84, blue: 0.69)
        case .display: Color(red: 0.73, green: 0.53, blue: 1.0)
        case .diagnostics: AgentMeterTheme.warning
        }
    }
}
