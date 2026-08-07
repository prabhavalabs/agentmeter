import Observation
import ServiceManagement

@MainActor
@Observable
public final class LaunchAtLoginController {
    public private(set) var isEnabled: Bool
    public private(set) var isUpdating = false
    public private(set) var errorMessage: String?

    public init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    public func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Registers the app as a login item on first run so it survives
    /// restarts out of the box. Runs once; an explicit user choice in
    /// Settings is recorded as configured and is never overridden.
    public func enableByDefaultIfUnconfigured(preferences: AppPreferences) async {
        guard preferences.launchAtLoginConfigured == false else { return }
        preferences.launchAtLoginConfigured = true
        let succeeded = await setEnabled(true)
        preferences.launchAtLogin = succeeded
    }

    public func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled != isEnabled else { return true }
        isUpdating = true
        errorMessage = nil
        defer { isUpdating = false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try await SMAppService.mainApp.unregister()
            }
            refresh()
            return isEnabled == enabled
        } catch {
            refresh()
            errorMessage = error.localizedDescription
            return false
        }
    }
}
