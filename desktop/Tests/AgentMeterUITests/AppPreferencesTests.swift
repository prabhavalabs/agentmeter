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
    #expect(preferences.notificationsEnabled)
}
