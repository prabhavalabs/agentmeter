import AgentMeterCore
import SwiftUI

public struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedProvider: ProviderSummary?

    public init() {}

    public var body: some View {
        let providers = visibleProviders
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                metrics
                if providers.isEmpty == false {
                    UsageTrendChart(
                        samples: model.historySamples,
                        providers: providers,
                        range: model.historyRange
                    ) { range in
                        Task { await model.loadHistory(range) }
                    }
                }
                providerSection(providers)
            }
            .padding(28)
        }
        .navigationTitle("Overview")
        .sheet(item: $selectedProvider) { provider in
            ProviderUsageDetailsView(provider: provider, nowEpoch: nowEpoch)
        }
        .onChange(of: model.requestedProviderDetailID, initial: true) { _, _ in
            selectRequestedProvider(from: providers)
        }
        .onChange(of: providers) { _, updatedProviders in
            selectRequestedProvider(from: updatedProviders)
        }
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

    private func providerSection(_ providers: [ProviderSummary]) -> some View {
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

            if providers.isEmpty {
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
                    ForEach(providers) { provider in
                        ProviderUsageCard(
                            provider: provider,
                            nowEpoch: nowEpoch,
                            onShowDetails: { selectedProvider = provider }
                        )
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

    private func selectRequestedProvider(from providers: [ProviderSummary]) {
        guard let requestedID = model.requestedProviderDetailID,
              let provider = providers.first(where: { $0.id == requestedID }) else {
            return
        }
        selectedProvider = provider
        model.completeRequestedProviderDetail(id: requestedID)
    }

    private var nowEpoch: Int { Int(Date().timeIntervalSince1970) }

}

private struct ProviderUsageCard: View {
    let provider: ProviderSummary
    let nowEpoch: Int
    let onShowDetails: () -> Void

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

            if secondaryWindows.isEmpty == false {
                Divider()
                VStack(spacing: 8) {
                    ForEach(secondaryWindows) { window in
                        HStack(spacing: 10) {
                            Text(window.label)
                                .lineLimit(1)
                            Spacer()
                            Text(UsageFormatting.percentage(window.usedPercent))
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(
                                    window.usedPercent == nil ? .secondary : .primary
                                )
                        }
                        .font(.caption)
                    }
                }
            }

            HStack {
                Text(UsageFormatting.updatedAge(
                    updatedAtEpoch: provider.updatedAtEpoch,
                    nowEpoch: nowEpoch
                ))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                Spacer()
                Button("Details", systemImage: "chevron.right", action: onShowDetails)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(accent)
            }
        }
        .padding(18)
        .frame(
            maxWidth: .infinity,
            minHeight: ProviderCardLayout.height(windowCount: provider.windows.count),
            maxHeight: ProviderCardLayout.height(windowCount: provider.windows.count),
            alignment: .topLeading
        )
        .agentMeterProviderCard(accent: accent)
        .accessibilityElement(children: .contain)
    }

    private var primaryWindow: ProviderWindow? { provider.windows.first }
    private var secondaryWindows: ArraySlice<ProviderWindow> { provider.windows.dropFirst() }
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

private struct ProviderUsageDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    let provider: ProviderSummary
    let nowEpoch: Int

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if usesSessionAndCycleLayout {
                        sessionAndCycleDetails
                    } else {
                        usageWindowDetails
                    }

                    Label(
                        "Usage is read locally from the signed-in provider tool. Missing values are never treated as zero.",
                        systemImage: "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
                .padding(24)
            }
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 500, idealHeight: 590)
        .background(AgentMeterTheme.windowBackground)
    }

    private var detailHeader: some View {
        HStack(spacing: 14) {
            ProviderMark(providerId: provider.id, name: provider.name, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(provider.name) usage")
                    .font(.title2.bold())
                HStack(spacing: 8) {
                    StatusPill(statusText, symbol: statusSymbol, tint: statusTint)
                    Text(UsageFormatting.updatedAge(
                        updatedAtEpoch: provider.updatedAtEpoch,
                        nowEpoch: nowEpoch
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Close usage details")
        }
        .padding(20)
    }

    @ViewBuilder
    private var sessionAndCycleDetails: some View {
        if let sessionWindow {
            detailSection("Current session") {
                UsageWindowPanel(
                    window: sessionWindow,
                    accent: accent,
                    nowEpoch: nowEpoch
                )
            }
        }

        if let cycleWindow {
            detailSection("Overall cycle") {
                UsageWindowPanel(
                    window: cycleWindow,
                    accent: accent,
                    nowEpoch: nowEpoch
                )
            }
        }

        if modelWindows.isEmpty == false {
            detailSection("Usage by model") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(modelWindows) { window in
                        UsageWindowPanel(
                            window: window,
                            accent: accent,
                            nowEpoch: nowEpoch
                        )
                    }
                }
            }
        }
    }

    private var usageWindowDetails: some View {
        detailSection("Usage windows") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: 12)],
                spacing: 12
            ) {
                ForEach(provider.windows) { window in
                    UsageWindowPanel(
                        window: window,
                        accent: accent,
                        nowEpoch: nowEpoch
                    )
                }
            }
        }
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private var usesSessionAndCycleLayout: Bool {
        provider.id == "claude" || provider.id == "codex"
    }

    private var sessionWindow: ProviderWindow? {
        provider.windows.first {
            $0.kind == "session" && $0.label.localizedCaseInsensitiveContains("session")
        }
    }

    private var cycleWindow: ProviderWindow? {
        provider.windows.first { $0.kind == "weekly" }
    }

    private var modelWindows: [ProviderWindow] {
        let excluded = Set([sessionWindow?.id, cycleWindow?.id].compactMap { $0 })
        return provider.windows.filter { excluded.contains($0.id) == false }
    }

    private var accent: Color { ProviderPalette.accent(for: provider.id) }

    private var statusText: String {
        switch provider.status {
        case "ok": "Live"
        case "stale": "Last known value"
        case "unavailable": "Unavailable"
        default: provider.status.capitalized
        }
    }

    private var statusSymbol: String {
        switch provider.status {
        case "ok": "waveform.path.ecg"
        case "stale": "clock.arrow.circlepath"
        default: "exclamationmark.circle"
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

private struct UsageWindowPanel: View {
    let window: ProviderWindow
    let accent: Color
    let nowEpoch: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label)
                    .font(.headline)
                Spacer()
                Text(valueText)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(window.usedPercent == nil ? .secondary : .primary)
            }

            if let percent = window.usedPercent {
                ProgressView(value: Double(percent), total: 100)
                    .tint(accent)
            } else {
                Label("Provider did not report a value", systemImage: "minus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(
                    UsageFormatting.resetCountdown(
                        resetAtEpoch: window.resetAtEpoch,
                        nowEpoch: nowEpoch
                    ),
                    systemImage: "clock"
                )
                if let resetAtEpoch = window.resetAtEpoch {
                    Text(
                        Date(timeIntervalSince1970: Double(resetAtEpoch)),
                        format: .dateTime
                            .weekday(.abbreviated)
                            .day()
                            .month(.abbreviated)
                            .hour()
                            .minute()
                    )
                    .padding(.leading, 20)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .agentMeterCard(emphasized: true)
    }

    private var valueText: String {
        window.usedPercent.map { "\($0)% used" } ?? "Not reported"
    }
}
