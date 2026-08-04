import AgentMeterUI
import AppKit
import SwiftUI

@main
@MainActor
struct AgentMeterApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppEnvironment.makeModel()
    @State private var launchAtLogin = LaunchAtLoginController()
    @State private var bridgeService = BridgeServiceController(
        externalMode: AppEnvironment.hasIPCOverride
    )
    @State private var powerObserver = WorkspacePowerObserver()
    @State private var notifications = UserNotificationController()

    var body: some Scene {
        WindowGroup("AgentMeter", id: "main") {
            RootView()
                .environment(model)
                .environment(launchAtLogin)
                .environment(bridgeService)
                .environment(powerObserver)
                .environment(notifications)
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
            CommandGroup(replacing: .appTermination) {
                Button("Quit AgentMeter") {
                    quit()
                }
                .keyboardShortcut("q")
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
                .environment(launchAtLogin)
                .environment(bridgeService)
                .environment(powerObserver)
                .environment(notifications)
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
                .environment(bridgeService)
                .environment(notifications)
                .preferredColorScheme(model.preferences.appearance.colorScheme)
        }
        .defaultSize(width: 520, height: 460)
        .windowResizability(.contentSize)
    }

    private func quit() {
        Task {
            await model.stop()
            await bridgeService.stop()
            NSApplication.shared.terminate(nil)
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ApplicationPresentationController.shared.windowWillOpen()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        ApplicationPresentationController.shared.lastWindowDidClose()
        return false
    }
}
