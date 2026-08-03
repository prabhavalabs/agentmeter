import AgentMeterCore
import AppKit
import SwiftUI

public struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(BridgeServiceController.self) private var bridgeService
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                ForEach(0 ..< pages.count, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? AgentMeterTheme.accent : Color.secondary.opacity(0.2))
                        .frame(width: index == step ? 34 : 10, height: 7)
                }
            }
            .padding(.top, 24)
            .animation(.easeInOut(duration: 0.18), value: step)

            currentPage

            Divider()
            HStack {
                Button("Set Up Later") { complete() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Button(step == pages.count - 1 ? "Finish" : "Continue") {
                    if step == pages.count - 1 { complete() } else { step += 1 }
                }
                .buttonStyle(.borderedProminent)
                .tint(AgentMeterTheme.accent)
            }
            .padding(20)
        }
        .frame(width: 680, height: 560)
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var currentPage: some View {
        switch step {
        case 0: bridgePage
        case 1: bluetoothPage
        case 2: devicePage
        case 3: securityPage
        default: providersPage
        }
    }

    private var bridgePage: some View {
        page(
            symbol: "point.3.connected.trianglepath.dotted",
            title: "Welcome to AgentMeter",
            message: "The private background bridge reads local agent usage and maintains the single Bluetooth connection to your display."
        ) {
            statusRow("Background bridge", value: bridgeService.state.title, good: bridgeService.state.isUsable)
            if bridgeService.isCommunityBuild {
                Text("This community build keeps its bridge running while AgentMeter remains open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let detail = bridgeService.state.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AgentMeterTheme.warning)
                    .multilineTextAlignment(.center)
            }
            if bridgeService.state == .needsApproval {
                Button("Open Login Items") { bridgeService.openLoginItemsSettings() }
            } else if bridgeService.state.isUsable == false {
                Button("Try Again") { Task { await bridgeService.retry() } }
            }
        }
    }

    private var bluetoothPage: some View {
        page(
            symbol: "antenna.radiowaves.left.and.right",
            title: "Allow Bluetooth",
            message: "Scanning prompts macOS for Bluetooth permission when needed. AgentMeter communicates only with compatible displays."
        ) {
            statusRow("Bluetooth", value: model.state.connection.phase.displayName, good: model.state.connection.phase != .bluetoothUnavailable)
            operationButton(
                title: "Scan for AgentMeter",
                workingTitle: "Scanning…",
                symbol: "dot.radiowaves.left.and.right",
                operation: .scanning
            ) {
                await model.scan()
            }
                .disabled(model.activeOperations.contains(.scanning))
            if model.state.connection.phase == .bluetoothUnavailable {
                Button("Open Bluetooth Settings") { openBluetoothSettings() }
            }
        }
    }

    private var devicePage: some View {
        page(
            symbol: "display",
            title: "Choose Your Display",
            message: "Select the AgentMeter unit you want this Mac to manage. The bridge remembers your choice and reconnects automatically."
        ) {
            if model.discoveredDevices.isEmpty {
                Text("No displays found yet. Keep the unit powered on and nearby, then scan again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                operationButton(
                    title: "Scan Again",
                    workingTitle: "Scanning…",
                    symbol: "arrow.clockwise",
                    operation: .scanning
                ) {
                    await model.scan()
                }
            } else {
                ForEach(model.discoveredDevices.prefix(4)) { peripheral in
                    Button {
                        Task { await model.connect(to: peripheral.identifier) }
                    } label: {
                        HStack {
                            Image(systemName: "display")
                            Text(peripheral.name)
                            Spacer()
                            Text(peripheral.rssi.map { "\($0) dBm" } ?? "Signal unavailable")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                        }
                        .padding(10)
                    }
                    .buttonStyle(.plain)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var securityPage: some View {
        page(
            symbol: "lock.shield.fill",
            title: "Private, Encrypted Control",
            message: "Usage snapshots and device controls travel over encrypted Bluetooth. Credentials, prompts, and source code never leave your Mac."
        ) {
            statusRow(
                "Device connection",
                value: model.state.connection.phase.displayName,
                good: model.state.connection.phase == .connected
            )
            statusRow(
                "Management channel",
                value: model.state.connection.managementAvailable == true ? "Available" : "Waiting for device",
                good: model.state.connection.managementAvailable == true
            )
        }
    }

    private var providersPage: some View {
        page(
            symbol: "sparkles",
            title: "Load Agent Usage",
            message: "AgentMeter reads supported coding-agent sessions already available on this Mac. You can choose visibility and ordering at any time."
        ) {
            statusRow(
                "Coding agents",
                value: model.state.providers.isEmpty ? "Not loaded" : "\(model.state.providers.count) available",
                good: model.state.providers.isEmpty == false
            )
            operationButton(
                title: "Refresh Usage",
                workingTitle: "Refreshing…",
                symbol: "arrow.clockwise",
                operation: .providerRefresh
            ) {
                await model.refreshProviders()
            }
                .disabled(model.activeOperations.contains(.providerRefresh))
        }
    }

    private func operationButton(
        title: String,
        workingTitle: String,
        symbol: String,
        operation: AppOperation,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            if model.activeOperations.contains(operation) {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(workingTitle)
                }
            } else {
                Label(title, systemImage: symbol)
            }
        }
    }

    private func page<Content: View>(
        symbol: String,
        title: String,
        message: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AgentMeterTheme.accent.opacity(0.12))
                Image(systemName: symbol)
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(AgentMeterTheme.accent)
            }
            .frame(width: 104, height: 104)
            Text(title).font(.largeTitle.bold())
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            VStack(spacing: 12) { content() }
                .frame(maxWidth: 460)
            Spacer()
        }
        .padding(.horizontal, 36)
    }

    private func statusRow(_ title: String, value: String, good: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Label(value, systemImage: good ? "checkmark.circle.fill" : "clock")
                .foregroundStyle(good ? AgentMeterTheme.success : AgentMeterTheme.warning)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func complete() {
        model.preferences.onboardingComplete = true
        dismiss()
    }

    private func openBluetoothSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Bluetooth-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private var pages: [String] { ["Bridge", "Bluetooth", "Device", "Security", "Agents"] }
}
