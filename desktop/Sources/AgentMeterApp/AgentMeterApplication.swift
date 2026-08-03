import AgentMeterUI
import AppKit
import SwiftUI

@main
@MainActor
struct AgentMeterApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppEnvironment.makeModel()
    @State private var launchAtLogin = LaunchAtLoginController()

    var body: some Scene {
        WindowGroup("AgentMeter", id: "main") {
            RootView()
                .environment(model)
                .environment(launchAtLogin)
                .preferredColorScheme(model.preferences.appearance.colorScheme)
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Overview") { model.selectedSection = .overview }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Device") { model.selectedSection = .device }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Agents") { model.selectedSection = .agents }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Display") { model.selectedSection = .display }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Diagnostics") { model.selectedSection = .diagnostics }
                    .keyboardShortcut("5", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
                .environment(launchAtLogin)
                .preferredColorScheme(model.preferences.appearance.colorScheme)
        } label: {
            Image(systemName: model.state.connection.phase.symbolName)
                .accessibilityLabel("AgentMeter: \(model.state.connection.phase.displayName)")
        }
        .menuBarExtraStyle(.window)

        Settings {
            AppSettingsView()
                .environment(model)
                .environment(launchAtLogin)
                .preferredColorScheme(model.preferences.appearance.colorScheme)
        }
        .defaultSize(width: 500, height: 360)
        .windowResizability(.contentSize)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
