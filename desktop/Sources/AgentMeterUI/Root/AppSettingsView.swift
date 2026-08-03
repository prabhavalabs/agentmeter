import SwiftUI

public struct AppSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(LaunchAtLoginController.self) private var launchAtLogin

    public init() {}

    public var body: some View {
        @Bindable var preferences = model.preferences
        Form {
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

            Section("Notifications") {
                Toggle("Usage and connection alerts", isOn: $preferences.notificationsEnabled)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 500, height: 360)
        .onAppear { launchAtLogin.refresh() }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { enabled in
                Task {
                    let saved = await launchAtLogin.setEnabled(enabled)
                    if saved {
                        model.preferences.launchAtLogin = enabled
                    }
                }
            }
        )
    }
}
