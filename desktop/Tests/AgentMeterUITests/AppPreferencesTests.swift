import AgentMeterUI
import Foundation
import Testing

@MainActor
@Test func appearanceDefaultsToSystemAndRoundTrips() {
    let suiteName = "AgentMeterPreferencesTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let preferences = AppPreferences(defaults: defaults)
    #expect(preferences.appearance == .system)
    #expect(preferences.selectedSection == .overview)

    preferences.appearance = .light
    preferences.selectedSection = .display

    let restored = AppPreferences(defaults: defaults)
    #expect(restored.appearance == .light)
    #expect(restored.selectedSection == .display)
}

@MainActor
@Test func preferenceDefaultsAreSafeAndBounded() {
    let suiteName = "AgentMeterPreferencesTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("future-theme", forKey: "appearance")
    defaults.set("future-section", forKey: "selectedSection")

    let preferences = AppPreferences(defaults: defaults)

    #expect(preferences.appearance == .system)
    #expect(preferences.selectedSection == .overview)
    #expect(preferences.sidebarVisible)
    #expect(preferences.notificationsEnabled == false)
}

@MainActor
@Test func launchAtLoginDefaultRegistrationRunsExactlyOnce() async {
    let defaults = UserDefaults(suiteName: "launch-at-login-default-\(UUID().uuidString)")!
    let preferences = AppPreferences(defaults: defaults)

    #expect(preferences.launchAtLoginConfigured == false)

    // First run claims the one-time default registration.
    preferences.launchAtLoginConfigured = true
    preferences.launchAtLogin = true

    let reloaded = AppPreferences(defaults: defaults)
    #expect(reloaded.launchAtLoginConfigured == true)
    #expect(reloaded.launchAtLogin == true)
}
