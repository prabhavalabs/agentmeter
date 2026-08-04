import AgentMeterCore
import AppKit
import SwiftUI

public struct DeviceScannerPresentation: Equatable, Sendable {
    public let isScanning: Bool
    public let hasDevices: Bool

    public init(isScanning: Bool, hasDevices: Bool) {
        self.isScanning = isScanning
        self.hasDevices = hasDevices
    }

    public var emptyTitle: String {
        isScanning ? "Searching nearby" : "No AgentMeters found"
    }

    public var emptyDescription: String {
        isScanning
            ? "Keep the AgentMeter powered and close to this Mac."
            : "Make sure the display is powered on and not connected to another Mac, then scan again."
    }

    public var scanButtonTitle: String {
        isScanning ? "Scanning…" : "Scan Again"
    }

    public var showsScanProgress: Bool { isScanning }
}

private struct DeviceScannerEmptyState: View {
    let presentation: DeviceScannerPresentation

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(AgentMeterTheme.accent)
                .frame(width: 48, height: 48)
                .background(
                    AgentMeterTheme.accent.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )

            VStack(spacing: 6) {
                Text(presentation.emptyTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(presentation.emptyDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

public struct DeviceView: View {
    @Environment(AppModel.self) private var model
    @State private var showingScanner = false
    @State private var confirmingForget = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                connectionCard
                if requiresManagementFirmware {
                    managementFirmwareNotice
                }
                if let information = model.state.information {
                    informationSection(information)
                }
                telemetrySection
            }
            .padding(28)
        }
        .navigationTitle("Device")
        .sheet(isPresented: $showingScanner) { scannerSheet }
        .confirmationDialog(
            "Forget this AgentMeter?",
            isPresented: $confirmingForget,
            titleVisibility: .visible
        ) {
            Button("Forget Device", role: .destructive) {
                Task { await model.forgetDevice() }
            }
        } message: {
            Text("This clears the saved device and asks the ESP32 to clear its saved host bond.")
        }
    }

    private var connectionCard: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 28))
                .foregroundStyle(model.state.connection.phase.tint)
                .frame(width: 54, height: 54)
                .background(model.state.connection.phase.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text(model.state.connection.selectedDeviceName ?? "No device selected")
                    .font(.title2.bold())
                StatusPill(
                    model.state.connection.phase.displayName,
                    symbol: model.state.connection.phase.symbolName,
                    tint: model.state.connection.phase.tint
                )
                if let rssi = model.state.connection.rssi {
                    Text("Signal \(signalDescription(rssi)) · \(rssi) dBm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack {
                Button("Find Device…", systemImage: "dot.radiowaves.left.and.right") {
                    showingScanner = true
                    Task { await model.scan() }
                }
                if model.state.connection.phase == .connected {
                    if model.state.connection.managementAvailable == true {
                        Button("Identify", systemImage: "light.beacon.max") {
                            Task { await model.identifyDevice() }
                        }
                    }
                    Button("Disconnect") { Task { await model.disconnect() } }
                } else {
                    Button("Reconnect") { Task { await model.reconnect() } }
                        .buttonStyle(.borderedProminent)
                }
                Menu {
                    Button("Refresh device state") { Task { await model.refreshDevice() } }
                        .disabled(model.state.connection.managementAvailable != true)
                    Divider()
                    Button("Forget Device…", role: .destructive) { confirmingForget = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }
            .disabled(model.activeOperations.contains(.deviceConnection))
        }
        .padding(20)
        .agentMeterCard(emphasized: true)
    }

    private var managementFirmwareNotice: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(AgentMeterTheme.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text("Legacy device firmware detected").font(.headline)
                Text("Bluetooth usage updates still work, but telemetry, display controls, Identify, and two-way settings need the current firmware. Connect the device to this Mac with a USB-C data cable for a one-time firmware install.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .agentMeterCard()
    }

    private func informationSection(_ information: DeviceInformation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Device information").font(.title3.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                MetricCard(title: "Model", value: information.model, symbol: "display")
                MetricCard(title: "Firmware", value: information.firmwareVersion, symbol: "cpu")
                MetricCard(title: "Hardware", value: information.hardwareRevision, symbol: "memorychip")
                MetricCard(
                    title: "Management",
                    value: "Schema \(information.managementSchemaVersion)",
                    symbol: "lock.shield"
                )
            }
        }
    }

    private var telemetrySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Power and health").font(.title3.bold())
            if let telemetry = model.state.telemetry {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                    MetricCard(
                        title: "Power source",
                        value: TelemetryFormatting.powerSource(telemetry.powerSource),
                        symbol: "cable.connector"
                    )
                    MetricCard(
                        title: "Battery",
                        value: TelemetryFormatting.battery(
                            present: telemetry.batteryPresent,
                            percent: telemetry.batteryPercent
                        ),
                        symbol: "battery.100percent"
                    )
                    MetricCard(
                        title: "USB voltage",
                        value: TelemetryFormatting.millivolts(telemetry.vbusVoltageMv),
                        symbol: "bolt"
                    )
                    MetricCard(
                        title: "Input current",
                        value: telemetry.inputCurrentMa.map { "\($0) mA" } ?? "Unavailable",
                        symbol: "bolt.horizontal"
                    )
                    MetricCard(
                        title: "Uptime",
                        value: TelemetryFormatting.uptime(telemetry.uptimeSeconds),
                        symbol: "clock.arrow.circlepath"
                    )
                    MetricCard(
                        title: "Display",
                        value: displayState(telemetry),
                        symbol: "sun.max"
                    )
                    MetricCard(
                        title: "Free memory",
                        value: byteCount(telemetry.freeHeapBytes),
                        symbol: "memorychip"
                    )
                    MetricCard(
                        title: "Board temperature",
                        value: telemetry.boardTemperatureC.map { String(format: "%.1f °C", $0) } ?? "Unavailable",
                        symbol: "thermometer.medium"
                    )
                }
            } else {
                ContentUnavailableView(
                    requiresManagementFirmware ? "Firmware update required" : "Telemetry unavailable",
                    systemImage: requiresManagementFirmware
                        ? "externaldrive.badge.exclamationmark"
                        : "waveform.path.ecg",
                    description: Text(
                        requiresManagementFirmware
                            ? "The connected legacy firmware does not expose telemetry. Install the current firmware by USB-C to enable live power and health data."
                            : "Connect an AgentMeter to view live device health."
                    )
                )
                .frame(maxWidth: .infinity, minHeight: 180)
                .agentMeterCard()
            }
        }
    }

    private var requiresManagementFirmware: Bool {
        model.state.connection.phase == .connected
            && model.state.connection.managementAvailable == false
    }

    private var scannerSheet: some View {
        let presentation = DeviceScannerPresentation(
            isScanning: model.activeOperations.contains(.scanning),
            hasDevices: model.discoveredDevices.isEmpty == false
        )
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nearby AgentMeters").font(.title2.bold())
                    Text("Only compatible Bluetooth devices are shown.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await model.scan() } } label: {
                    HStack(spacing: 8) {
                        if presentation.showsScanProgress {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(presentation.scanButtonTitle)
                    }
                    .frame(width: 108)
                }
                .disabled(presentation.isScanning)
            }
            Divider()
            if model.state.connection.phase == .bluetoothUnavailable {
                ContentUnavailableView {
                    Label("Bluetooth unavailable", systemImage: "antenna.radiowaves.left.and.right.slash")
                } description: {
                    Text("Turn on Bluetooth and allow AgentMeter access in System Settings.")
                } actions: {
                    Button("Open Bluetooth Settings") { openBluetoothSettings() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if presentation.hasDevices == false {
                DeviceScannerEmptyState(presentation: presentation)
            } else {
                List(model.discoveredDevices) { peripheral in
                    HStack {
                        Image(systemName: "display")
                            .foregroundStyle(AgentMeterTheme.accent)
                        VStack(alignment: .leading) {
                            Text(peripheral.name).font(.headline)
                            Text(peripheral.rssi.map { "\($0) dBm" } ?? "Signal unavailable")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Connect") {
                            Task {
                                await model.connect(to: peripheral.identifier)
                                showingScanner = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { showingScanner = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(
            minWidth: 620,
            idealWidth: 660,
            maxWidth: 680,
            minHeight: 420,
            idealHeight: 440,
            maxHeight: 480
        )
    }

    private func signalDescription(_ rssi: Int) -> String {
        if rssi >= -55 { return "Excellent" }
        if rssi >= -70 { return "Good" }
        if rssi >= -82 { return "Fair" }
        return "Weak"
    }

    private func displayState(_ telemetry: DeviceTelemetry) -> String {
        if telemetry.displayOn == false { return "Off" }
        if telemetry.displayDimmed == true { return "Dimmed" }
        return telemetry.displayOn == true ? "On" : "Unavailable"
    }

    private func byteCount(_ bytes: Int?) -> String {
        guard let bytes else { return "Unavailable" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    private func openBluetoothSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Bluetooth-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
