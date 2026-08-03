import Foundation

public enum NavigationSection: String, CaseIterable, Codable, Identifiable, Sendable {
    case overview
    case device
    case agents
    case display
    case diagnostics

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .device: "Device"
        case .agents: "Agents"
        case .display: "Display"
        case .diagnostics: "Diagnostics"
        }
    }

    public var symbolName: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .device: "display"
        case .agents: "sparkles"
        case .display: "slider.horizontal.3"
        case .diagnostics: "waveform.path.ecg"
        }
    }
}
