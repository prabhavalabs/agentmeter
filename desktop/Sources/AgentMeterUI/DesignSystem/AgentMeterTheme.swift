import AgentMeterCore
import SwiftUI

public enum AgentMeterTheme {
    public static let accent = Color(red: 0.55, green: 0.49, blue: 1.0)
    public static let windowBackground = Color(nsColor: .windowBackgroundColor)
    public static let surface = Color(nsColor: .controlBackgroundColor)
    public static let raisedSurface = Color(nsColor: .underPageBackgroundColor)
    public static let border = Color(nsColor: .separatorColor)
    public static let secondaryText = Color(nsColor: .secondaryLabelColor)
    public static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    public static let success = Color(red: 0.28, green: 0.76, blue: 0.42)
    public static let warning = Color(red: 0.96, green: 0.66, blue: 0.22)
    public static let critical = Color(red: 0.95, green: 0.31, blue: 0.34)
}

public enum ProviderPalette {
    public static func accentHex(for providerId: String) -> UInt32 {
        switch providerId.lowercased() {
        case "codex": 0x52E3B2
        case "claude": 0xF2A36B
        case "gemini": 0x5EC8FF
        case "cursor": 0xD6D5CC
        default: 0x8B7CFF
        }
    }

    public static func accent(for providerId: String) -> Color {
        let value = accentHex(for: providerId)
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

enum ProviderCardLayout {
    static func height(windowCount _: Int) -> CGFloat { 270 }
}

public extension AppearancePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

public extension ConnectionPhase {
    var displayName: String {
        switch self {
        case .stopped: "Disconnected"
        case .bluetoothUnavailable: "Bluetooth unavailable"
        case .searching: "Searching"
        case .connecting: "Connecting"
        case .authenticating: "Securing connection"
        case .synchronizing: "Synchronizing"
        case .connected: "Connected"
        case .degraded: "Needs attention"
        case .retrying: "Reconnecting"
        }
    }

    var symbolName: String {
        switch self {
        case .connected: "checkmark.circle.fill"
        case .searching, .connecting, .authenticating, .synchronizing, .retrying:
            "arrow.triangle.2.circlepath"
        case .degraded, .bluetoothUnavailable: "exclamationmark.triangle.fill"
        case .stopped: "circle"
        }
    }

    var tint: Color {
        switch self {
        case .connected: AgentMeterTheme.success
        case .searching, .connecting, .authenticating, .synchronizing, .retrying:
            AgentMeterTheme.accent
        case .degraded, .bluetoothUnavailable: AgentMeterTheme.warning
        case .stopped: AgentMeterTheme.secondaryText
        }
    }
}

public struct CardStyle: ViewModifier {
    public var emphasized = false

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AgentMeterTheme.surface)
                    .shadow(color: .black.opacity(emphasized ? 0.10 : 0.05), radius: 10, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AgentMeterTheme.border.opacity(0.65), lineWidth: 1)
            )
    }
}

private struct ProviderCardStyle: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .background {
                ZStack(alignment: .top) {
                    shape.fill(AgentMeterTheme.surface)
                    LinearGradient(
                        colors: [
                            accent.opacity(0.18),
                            accent.opacity(0.055),
                            .clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 92)
                }
                .clipShape(shape)
                .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            }
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.32),
                            AgentMeterTheme.border.opacity(0.65),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
    }
}

public extension View {
    func agentMeterCard(emphasized: Bool = false) -> some View {
        modifier(CardStyle(emphasized: emphasized))
    }

    func agentMeterProviderCard(accent: Color) -> some View {
        modifier(ProviderCardStyle(accent: accent))
    }
}
