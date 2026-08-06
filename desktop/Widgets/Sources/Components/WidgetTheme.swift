import AgentMeterCore
import AgentMeterWidgetCore
import SwiftUI

struct WidgetThemePalette {
    let background: Color
    let primaryText: Color
    let secondaryText: Color
    let track: Color
    let accent: Color
    let preferredColorScheme: ColorScheme?

    init(theme: WidgetTheme, providerID: String) {
        let providerAccent = Color(providerAccentHex: ProviderVisuals.accentHex(for: providerID))
        accent = providerAccent

        switch theme {
        case .system:
            background = Color.primary.opacity(0.035)
            primaryText = .primary
            secondaryText = .secondary
            track = Color.secondary.opacity(0.18)
            preferredColorScheme = nil
        case .light:
            background = Color(red: 0.965, green: 0.97, blue: 0.98)
            primaryText = Color(red: 0.08, green: 0.09, blue: 0.12)
            secondaryText = Color(red: 0.32, green: 0.34, blue: 0.4)
            track = Color.black.opacity(0.12)
            preferredColorScheme = .light
        case .dark:
            background = Color(red: 0.105, green: 0.115, blue: 0.14)
            primaryText = Color.white.opacity(0.96)
            secondaryText = Color.white.opacity(0.65)
            track = Color.white.opacity(0.14)
            preferredColorScheme = .dark
        case .midnight:
            background = Color(red: 0.025, green: 0.045, blue: 0.09)
            primaryText = Color(red: 0.9, green: 0.95, blue: 1)
            secondaryText = Color(red: 0.62, green: 0.72, blue: 0.84)
            track = Color.white.opacity(0.12)
            preferredColorScheme = .dark
        case .neutral:
            background = Color.secondary.opacity(0.08)
            primaryText = .primary
            secondaryText = .secondary
            track = Color.secondary.opacity(0.2)
            preferredColorScheme = nil
        case .providerTinted:
            background = providerAccent.opacity(0.105)
            primaryText = .primary
            secondaryText = .secondary
            track = providerAccent.opacity(0.18)
            preferredColorScheme = nil
        }
    }
}

extension Color {
    init(providerAccentHex value: UInt32) {
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
