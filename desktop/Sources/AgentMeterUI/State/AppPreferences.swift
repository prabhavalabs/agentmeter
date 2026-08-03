import Foundation
import Observation

public enum AppearancePreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        rawValue.capitalized
    }
}

@MainActor
@Observable
public final class AppPreferences {
    private enum Key {
        static let appearance = "appearance"
        static let selectedSection = "selectedSection"
        static let sidebarVisible = "sidebarVisible"
        static let onboardingComplete = "onboardingComplete"
        static let launchAtLogin = "launchAtLogin"
        static let notificationsEnabled = "notificationsEnabled"
    }

    @ObservationIgnored private let defaults: UserDefaults

    public var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    public var selectedSection: NavigationSection {
        didSet { defaults.set(selectedSection.rawValue, forKey: Key.selectedSection) }
    }

    public var sidebarVisible: Bool {
        didSet { defaults.set(sidebarVisible, forKey: Key.sidebarVisible) }
    }

    public var onboardingComplete: Bool {
        didSet { defaults.set(onboardingComplete, forKey: Key.onboardingComplete) }
    }

    public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    public var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = AppearancePreference(
            rawValue: defaults.string(forKey: Key.appearance) ?? ""
        ) ?? .system
        selectedSection = NavigationSection(
            rawValue: defaults.string(forKey: Key.selectedSection) ?? ""
        ) ?? .overview
        sidebarVisible = defaults.object(forKey: Key.sidebarVisible) as? Bool ?? true
        onboardingComplete = defaults.bool(forKey: Key.onboardingComplete)
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? false
    }
}
