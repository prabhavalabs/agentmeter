import SwiftUI

/// Single source of truth for the application settings body. Rendered by the
/// standard ⌘, Settings window (wrapped in AppSettingsView) and by the main
/// window's Settings sidebar section (ApplicationSettingsSectionView).
public struct ApplicationSettingsForm: View {
    @Environment(AppModel.self) private var model
    @Environment(LaunchAtLoginController.self) private var launchAtLogin
    @Environment(BridgeServiceController.self) private var bridgeService
    @Environment(UserNotificationController.self) private var notifications

    public init() {}

    public var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section("Device") {
                Toggle("Sync with AgentMeter display", isOn: deviceSyncBinding)
                    .disabled(model.activeOperations.contains(.settings))
                Text(
                    model.deviceSyncEnabled
                        ? "Usage updates stream to the paired display over Bluetooth."
                        : "Standalone mode. Bluetooth is off and the app works as a desktop-only usage monitor. The paired display will show its data as stale."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Theme", selection: $preferences.appearance) {
                    ForEach(AppearancePreference.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                Text("System follows the appearance selected in macOS Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                if bridgeService.isCommunityBuild {
                    LabeledContent("Launch at login", value: "Configure in macOS")
                    Text("Add AgentMeter under General → Login Items to start this community build automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items") { bridgeService.openLoginItemsSettings() }
                } else {
                    Toggle("Launch AgentMeter at login", isOn: launchAtLoginBinding)
                        .disabled(launchAtLogin.isUpdating)
                    Text("Keeps the menu-bar status and device synchronization available after you sign in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let error = launchAtLogin.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(AgentMeterTheme.warning)
                    }
                }
                LabeledContent("Background bridge", value: bridgeService.state.title)
                if bridgeService.isCommunityBuild {
                    Text("Community builds keep the bundled bridge running while AgentMeter is open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if case let .failed(message) = bridgeService.state {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(AgentMeterTheme.warning)
                    Button("Try Again") { Task { await bridgeService.retry() } }
                } else if bridgeService.state == .needsApproval {
                    Text("Allow AgentMeter in Login Items, then try again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items") { bridgeService.openLoginItemsSettings() }
                }
            }

            Section("Notifications") {
                Toggle("Usage and connection alerts", isOn: notificationBinding)
                    .disabled(notifications.isUpdating)
                Text("Alerts cover usage thresholds, allowance resets, and connections lost for more than one minute.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = notifications.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(AgentMeterTheme.warning)
                    if error == UserNotificationController.deniedMessage {
                        Button("Open Notification Settings") {
                            UserNotificationController.openSystemNotificationSettings()
                        }
                    }
                }
            }

            Section("Setup") {
                Button("Run Setup Assistant Again…") {
                    model.preferences.onboardingComplete = false
                }
                Text("Revisit bridge, Bluetooth, display, security, and agent checks without removing current settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin.refresh() }
    }

    private var deviceSyncBinding: Binding<Bool> {
        Binding(
            get: { model.deviceSyncEnabled },
            set: { enabled in
                Task { await model.setDeviceSync(enabled) }
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { enabled in
                Task {
                    model.preferences.launchAtLoginConfigured = true
                    let saved = await launchAtLogin.setEnabled(enabled)
                    if saved {
                        model.preferences.launchAtLogin = enabled
                    }
                }
            }
        )
    }

    private var notificationBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.notificationsEnabled },
            set: { enabled in
                Task {
                    let saved = await notifications.setEnabled(enabled)
                    model.preferences.notificationsEnabled = enabled && saved
                }
            }
        )
    }
}

/// The main window's Settings section — the same settings body the ⌘,
/// window shows, laid out like the other sidebar pages.
public struct ApplicationSettingsSectionView: View {
    public init() {}

    public var body: some View {
        ApplicationSettingsForm()
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Settings")
    }
}

/// Fallback for device-scoped pages reached while device sync is off — a
/// stale stored selection or a deep link. The sidebar itself hides them.
struct DeviceSyncOffView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Device sync is off", systemImage: "bolt.slash")
        } description: {
            Text("AgentMeter is running as a desktop-only usage monitor.")
        } actions: {
            Button("Open Settings") { model.selectedSection = .settings }
        }
    }
}
