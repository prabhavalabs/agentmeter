import Foundation

public enum NavigationSection: String, CaseIterable, Codable, Identifiable, Sendable {
    case overview
    case device
    case agents
    case display
    case diagnostics
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .device: "Device"
        case .agents: "Agents"
        case .display: "Display"
        case .diagnostics: "Diagnostics"
        case .settings: "Settings"
        }
    }

    public var symbolName: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .device: "display"
        case .agents: "sparkles"
        case .display: "slider.horizontal.3"
        case .diagnostics: "waveform.path.ecg"
        case .settings: "gearshape"
        }
    }

    /// Sections that only make sense while the bridge synchronizes with the
    /// paired AgentMeter display.
    public var requiresDeviceSync: Bool {
        self == .device || self == .display
    }

    /// The sidebar sections available for the current device-sync mode, in
    /// display order.
    public static func visibleSections(deviceSyncEnabled: Bool) -> [NavigationSection] {
        allCases.filter { deviceSyncEnabled || $0.requiresDeviceSync == false }
    }

    /// Keeps a stored or deep-linked selection valid for the current
    /// device-sync mode, falling back to the overview.
    public static func resolvedSelection(
        _ current: NavigationSection,
        deviceSyncEnabled: Bool
    ) -> NavigationSection {
        visibleSections(deviceSyncEnabled: deviceSyncEnabled).contains(current)
            ? current
            : .overview
    }
}
