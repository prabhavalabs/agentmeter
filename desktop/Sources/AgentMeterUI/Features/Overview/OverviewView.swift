import AgentMeterCore
import SwiftUI

public struct OverviewView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                metrics
                providerSection
            }
            .padding(28)
        }
        .navigationTitle("Overview")
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AgentMeterTheme.accent.opacity(0.14))
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(AgentMeterTheme.accent)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text("AgentMeter")
                        .font(.largeTitle.bold())
                    StatusPill(
                        model.state.connection.phase.displayName,
                        symbol: model.state.connection.phase.symbolName,
                        tint: model.state.connection.phase.tint
                    )
                }
                Label(
                    model.state.connection.selectedDeviceName ?? "No device selected",
                    systemImage: "display"
                )
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Device Settings", systemImage: "gearshape") {
                model.selectedSection = .display
            }
            .buttonStyle(.borderedProminent)
            .tint(AgentMeterTheme.accent)
        }
    }

    private var metrics: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 12)],
            spacing: 12
        ) {
            MetricCard(
                title: "Bluetooth",
                value: model.state.connection.phase.displayName,
                symbol: "antenna.radiowaves.left.and.right",
                tint: model.state.connection.phase.tint
            )
            MetricCard(
                title: "Power",
                value: TelemetryFormatting.powerSource(model.state.telemetry?.powerSource),
                symbol: "cable.connector"
            )
            MetricCard(
                title: "Battery",
                value: TelemetryFormatting.battery(
                    present: model.state.telemetry?.batteryPresent,
                    percent: model.state.telemetry?.batteryPercent
                ),
                symbol: "battery.100percent"
            )
            MetricCard(
                title: "Firmware",
                value: model.state.information?.firmwareVersion ?? "Unavailable",
                symbol: "cpu"
            )
            MetricCard(
                title: "Last sync",
                value: UsageFormatting.updatedAge(
                    updatedAtEpoch: model.state.bridge.lastDeviceSyncEpoch,
                    nowEpoch: nowEpoch
                ).replacingOccurrences(of: "Updated ", with: ""),
                symbol: "clock"
            )
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Coding agents")
                        .font(.title2.bold())
                    Text("Current session windows from the local bridge")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Manage", systemImage: "slider.horizontal.3") {
                    model.selectedSection = .agents
                }
            }

            if visibleProviders.isEmpty {
                ContentUnavailableView(
                    "No usage available",
                    systemImage: "sparkles",
                    description: Text("Refresh providers or choose which agents appear on the device.")
                )
                .frame(maxWidth: .infinity, minHeight: 210)
                .agentMeterCard()
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(visibleProviders) { provider in
                        ProviderUsageCard(provider: provider, nowEpoch: nowEpoch)
                    }
                }
            }
        }
    }

    private var visibleProviders: [ProviderSummary] {
        let hidden = Set(model.state.settings?.hiddenProviderIds ?? [])
        let order = model.state.settings?.providerOrder ?? model.state.providers.map(\.id)
        return model.state.providers
            .filter { hidden.contains($0.id) == false }
            .sorted {
                (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max)
            }
    }

    private var nowEpoch: Int { Int(Date().timeIntervalSince1970) }
}

private struct ProviderUsageCard: View {
    let provider: ProviderSummary
    let nowEpoch: Int

    var body: some View {
        let accent = ProviderPalette.accent(for: provider.id)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ProviderMark(providerId: provider.id, name: provider.name, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.name)
                        .font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusTint)
                }
                Spacer()
                UsageRing(percent: primaryWindow?.usedPercent, tint: accent)
                    .frame(width: 62, height: 62)
            }

            if let primaryWindow {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(primaryWindow.label)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(UsageFormatting.percentage(primaryWindow.usedPercent))
                            .font(.title2.bold().monospacedDigit())
                    }
                    ProgressView(value: Double(primaryWindow.usedPercent ?? 0), total: 100)
                        .tint(primaryWindow.usedPercent == nil ? .secondary : accent)
                    Label(
                        UsageFormatting.resetCountdown(
                            resetAtEpoch: primaryWindow.resetAtEpoch,
                            nowEpoch: nowEpoch
                        ),
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("Usage is currently unavailable")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(UsageFormatting.updatedAge(updatedAtEpoch: provider.updatedAtEpoch, nowEpoch: nowEpoch))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .agentMeterCard(emphasized: true)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(accent)
                .frame(height: 2)
                .clipShape(.rect(topLeadingRadius: 14, topTrailingRadius: 14))
        }
        .accessibilityElement(children: .contain)
    }

    private var primaryWindow: ProviderWindow? { provider.windows.first }
    private var statusText: String {
        switch provider.status {
        case "ok": "Live"
        case "stale": "Last known value"
        case "unavailable": "Unavailable"
        default: provider.status.capitalized
        }
    }

    private var statusTint: Color {
        switch provider.status {
        case "ok": AgentMeterTheme.success
        case "stale": AgentMeterTheme.warning
        default: AgentMeterTheme.secondaryText
        }
    }
}
