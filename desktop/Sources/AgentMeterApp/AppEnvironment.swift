import AgentMeterIPC
import AgentMeterUI
import Darwin
import Foundation

@MainActor
enum AppEnvironment {
    static func makeModel() -> AppModel {
        let preferences = AppPreferences()
        let bridge = UnixBridgeClient(path: ipcPath)
        let widgetSnapshotCoordinator: any WidgetSnapshotCoordinating
        if let sharedContainerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.prabhavalabs.agentmeter.shared"
        ) {
            widgetSnapshotCoordinator = WidgetSnapshotCoordinator(
                bridge: bridge,
                directoryURL: sharedContainerURL,
                reloader: WidgetKitTimelineReloader()
            )
        } else {
            widgetSnapshotCoordinator = NoopWidgetSnapshotCoordinator()
        }
        return AppModel(
            bridge: bridge,
            preferences: preferences,
            widgetSnapshotCoordinator: widgetSnapshotCoordinator
        )
    }

    static var hasIPCOverride: Bool {
        ProcessInfo.processInfo.environment["AGENTMETER_IPC_PATH"]?.isEmpty == false
    }

    static var ipcPath: String {
        if let override = ProcessInfo.processInfo.environment["AGENTMETER_IPC_PATH"],
           override.isEmpty == false {
            return override
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("agentmeter-\(getuid())", isDirectory: true)
            .appendingPathComponent("bridge.sock", isDirectory: false)
            .path
    }
}
