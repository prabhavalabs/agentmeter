import AgentMeterCore
import SwiftUI

public struct DisplaySettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAlertEditor = false
    @State private var warningThreshold = 75
    @State private var criticalThreshold = 90

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Display settings").font(.largeTitle.bold())
                        Text("Changes are saved on the AgentMeter and stay active without the Mac.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    syncStatus
                }

                if let settings = model.state.settings {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            controls(settings).frame(minWidth: 430)
                            displayPreview(settings).frame(width: 300)
                        }
                        VStack(spacing: 18) {
                            controls(settings)
                            displayPreview(settings)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Settings unavailable",
                        systemImage: "slider.horizontal.3",
                        description: Text("Connect a management-capable AgentMeter to configure its display.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .agentMeterCard()
                }
            }
            .padding(28)
        }
        .navigationTitle("Display")
        .sheet(isPresented: $showingAlertEditor) { alertEditor }
    }

    private var syncStatus: some View {
        Group {
            switch model.settingsSyncState {
            case .synced:
                StatusPill("Synced", symbol: "checkmark.circle.fill", tint: AgentMeterTheme.success)
            case .saving:
                StatusPill("Saving", symbol: "arrow.triangle.2.circlepath", tint: AgentMeterTheme.accent)
            case .waitingForDevice:
                StatusPill("Waiting for device", symbol: "clock", tint: AgentMeterTheme.warning)
            }
        }
    }

    private func controls(_ settings: DeviceSettings) -> some View {
        VStack(spacing: 0) {
            settingRow(
                title: "Always-on display",
                detail: "Keep the AMOLED awake while AgentMeter has power.",
                symbol: "sun.max"
            ) {
                Toggle("", isOn: boolBinding(settings, keyPath: \.alwaysOn) { patch, value in
                    patch.alwaysOn = value
                })
                .labelsHidden()
            }
            Divider().padding(.leading, 58)
            settingRow(
                title: "Full-view mode",
                detail: "Show one agent at a time and rotate through visible agents.",
                symbol: "rectangle.inset.filled"
            ) {
                Toggle("", isOn: boolBinding(settings, keyPath: \.fullView) { patch, value in
                    patch.fullView = value
                })
                .labelsHidden()
            }
            Divider().padding(.leading, 58)
            settingRow(
                title: "Rotation interval",
                detail: "Time each agent remains visible in full-view mode.",
                symbol: "arrow.triangle.2.circlepath"
            ) {
                Picker("", selection: intBinding(settings.rotationSeconds) { patch, value in
                    patch.rotationSeconds = value
                }) {
                    ForEach([3, 5, 10, 15], id: \.self) { seconds in
                        Text("\(seconds) sec").tag(seconds)
                    }
                }
                .labelsHidden()
                .frame(width: 105)
                .disabled(settings.fullView == false)
            }
            Divider().padding(.leading, 58)
            settingRow(
                title: "Brightness",
                detail: "Active display brightness.",
                symbol: "sun.min"
            ) {
                Stepper(
                    "\(settings.brightnessPercent)%",
                    value: intBinding(settings.brightnessPercent) { patch, value in
                        patch.brightnessPercent = value
                    },
                    in: 10...100,
                    step: 5
                )
                .monospacedDigit()
                .disabled(model.state.information?.capabilities.brightness == false)
            }
            Divider().padding(.leading, 58)
            settingRow(
                title: "Dim after",
                detail: "Reduce brightness after inactivity.",
                symbol: "moon"
            ) {
                Picker("", selection: intBinding(settings.dimAfterSeconds) { patch, value in
                    patch.dimAfterSeconds = value
                }) {
                    durationOptions
                }
                .labelsHidden()
                .frame(width: 125)
                .disabled(settings.alwaysOn)
            }
            Divider().padding(.leading, 58)
            settingRow(
                title: "Turn off after",
                detail: "Switch the display off after inactivity.",
                symbol: "display.trianglebadge.exclamationmark"
            ) {
                Picker("", selection: intBinding(settings.screenOffAfterSeconds) { patch, value in
                    patch.screenOffAfterSeconds = value
                }) {
                    Text("5 min").tag(300)
                    Text("15 min").tag(900)
                    Text("30 min").tag(1800)
                    Text("1 hour").tag(3600)
                }
                .labelsHidden()
                .frame(width: 125)
                .disabled(settings.alwaysOn)
            }
            Divider().padding(.leading, 58)
            settingRow(
                title: "Usage alert thresholds",
                detail: "Change progress colours and supported device alerts.",
                symbol: "exclamationmark.triangle"
            ) {
                Button(settings.alertThresholds.map { "\($0)%" }.joined(separator: ", ")) {
                    let warning = min(max(settings.alertThresholds.first ?? 75, 10), 90)
                    warningThreshold = warning
                    criticalThreshold = min(
                        max(settings.alertThresholds.dropFirst().first ?? 90, warning + 5),
                        100
                    )
                    showingAlertEditor = true
                }
            }
            Divider().padding(.leading, 58)
            settingRow(
                title: "Alert sound",
                detail: "Play supported device alerts at configured thresholds.",
                symbol: "speaker.wave.2"
            ) {
                Toggle("", isOn: boolBinding(settings, keyPath: \.soundEnabled) { patch, value in
                    patch.soundEnabled = value
                })
                .labelsHidden()
            }
        }
        .agentMeterCard(emphasized: true)
        .disabled(model.activeOperations.contains(.settings))
    }

    private var alertEditor: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Usage alert thresholds").font(.title2.bold())
                Text("Warning and critical levels apply to every visible usage window.")
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 14) {
                Stepper(
                    "Warning at \(warningThreshold)%",
                    value: $warningThreshold,
                    in: 10...min(90, criticalThreshold - 5),
                    step: 5
                )
                Stepper(
                    "Critical at \(criticalThreshold)%",
                    value: $criticalThreshold,
                    in: max(15, warningThreshold + 5)...100,
                    step: 5
                )
            }
            .monospacedDigit()
            .padding(16)
            .agentMeterCard()
            HStack {
                Spacer()
                Button("Cancel") { showingAlertEditor = false }
                Button("Save") {
                    guard let settings = model.state.settings else { return }
                    var patch = DeviceSettingsPatch(baseRevision: settings.revision)
                    patch.alertThresholds = [warningThreshold, criticalThreshold]
                    showingAlertEditor = false
                    Task { await model.patchSettings(patch) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 430)
    }

    @ViewBuilder
    private var durationOptions: some View {
        Text("1 min").tag(60)
        Text("5 min").tag(300)
        Text("10 min").tag(600)
        Text("15 min").tag(900)
    }

    private func settingRow<Control: View>(
        title: String,
        detail: String,
        symbol: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .foregroundStyle(AgentMeterTheme.accent)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            control()
        }
        .padding(16)
    }

    private func displayPreview(_ settings: DeviceSettings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Device preview").font(.headline)
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.06, green: 0.07, blue: 0.10), Color(red: 0.10, green: 0.08, blue: 0.17)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(9)
                VStack(spacing: 14) {
                    HStack {
                        Image(systemName: "waveform.path.ecg").foregroundStyle(AgentMeterTheme.success)
                        Text("LIVE").font(.caption2.bold()).foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Image(systemName: "gearshape").foregroundStyle(.white.opacity(0.55))
                    }
                    if settings.fullView, let provider = previewProviders.first {
                        ProviderMark(providerId: provider.id, name: provider.name, size: 54)
                        Text(provider.name).font(.title2.bold()).foregroundStyle(.white)
                        UsageRing(percent: provider.windows.first?.usedPercent, tint: ProviderPalette.accent(for: provider.id))
                            .frame(width: 90, height: 90)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(previewProviders.prefix(4)) { provider in
                                VStack(spacing: 6) {
                                    ProviderMark(providerId: provider.id, name: provider.name, size: 30)
                                    Text(provider.name).font(.caption.bold()).foregroundStyle(.white)
                                    Text(UsageFormatting.percentage(provider.windows.first?.usedPercent))
                                        .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.75))
                                }
                                .frame(maxWidth: .infinity, minHeight: 72)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(26)
            }
            .aspectRatio(1, contentMode: .fit)
            Text(settings.fullView ? "Full view · rotates every \(settings.rotationSeconds) seconds" : "Responsive tile view")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .agentMeterCard()
    }

    private var previewProviders: [ProviderSummary] {
        let hidden = Set(model.state.settings?.hiddenProviderIds ?? [])
        return model.state.providers.filter { hidden.contains($0.id) == false }
    }

    private func boolBinding(
        _ settings: DeviceSettings,
        keyPath: KeyPath<DeviceSettings, Bool>,
        update: @escaping (inout DeviceSettingsPatch, Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                var patch = DeviceSettingsPatch(baseRevision: settings.revision)
                update(&patch, value)
                Task { await model.patchSettings(patch) }
            }
        )
    }

    private func intBinding(
        _ currentValue: Int,
        update: @escaping (inout DeviceSettingsPatch, Int) -> Void
    ) -> Binding<Int> {
        Binding(
            get: { currentValue },
            set: { value in
                guard let settings = model.state.settings else { return }
                var patch = DeviceSettingsPatch(baseRevision: settings.revision)
                update(&patch, value)
                Task { await model.patchSettings(patch) }
            }
        )
    }
}
