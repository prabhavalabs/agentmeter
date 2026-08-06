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

    init(theme: WidgetTheme, providerID: String, colorScheme: ColorScheme) {
        let providerBaseRGB = WidgetRGB(hex: ProviderVisuals.accentHex(for: providerID))
        let effectiveScheme = WidgetThemeContrastModel.effectiveScheme(
            theme: theme,
            requestedScheme: colorScheme
        )
        let contrastBackground = WidgetThemeContrastModel.background(
            theme: theme,
            requestedScheme: colorScheme,
            providerBaseAccent: providerBaseRGB
        )
        let resolvedAccent = WidgetAccentResolver.resolve(
            base: providerBaseRGB,
            against: contrastBackground,
            scheme: effectiveScheme
        )
        let providerAccent = Color(widgetRGB: resolvedAccent)
        let providerBaseAccent = Color(widgetRGB: providerBaseRGB)
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
            background = providerBaseAccent.opacity(0.105)
            primaryText = .primary
            secondaryText = .secondary
            track = providerAccent.opacity(0.18)
            preferredColorScheme = nil
        }
    }
}

struct WidgetRGB: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    init(hex value: UInt32) {
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    func mixed(with target: WidgetRGB, amount: Double) -> WidgetRGB {
        let amount = min(max(amount, 0), 1)
        return WidgetRGB(
            red: red + (target.red - red) * amount,
            green: green + (target.green - green) * amount,
            blue: blue + (target.blue - blue) * amount
        )
    }

    func contrastRatio(against other: WidgetRGB) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var relativeLuminance: Double {
        0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
    }

    private static func linear(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}

enum WidgetAccentResolver {
    static let minimumContrast = 3.0

    static func resolve(
        base: WidgetRGB,
        against background: WidgetRGB,
        scheme: ColorScheme
    ) -> WidgetRGB {
        let target = scheme == .light
            ? WidgetRGB(red: 0, green: 0, blue: 0)
            : WidgetRGB(red: 1, green: 1, blue: 1)
        for step in 8...100 {
            let candidate = base.mixed(with: target, amount: Double(step) / 100)
            if candidate.contrastRatio(against: background) >= minimumContrast {
                return candidate
            }
        }
        return target
    }
}

enum WidgetThemeContrastModel {
    static func effectiveScheme(theme: WidgetTheme, requestedScheme: ColorScheme) -> ColorScheme {
        switch theme {
        case .light: .light
        case .dark, .midnight: .dark
        case .system, .neutral, .providerTinted: requestedScheme
        }
    }

    static func background(
        theme: WidgetTheme,
        requestedScheme: ColorScheme,
        providerBaseAccent: WidgetRGB
    ) -> WidgetRGB {
        let scheme = effectiveScheme(theme: theme, requestedScheme: requestedScheme)
        switch theme {
        case .system:
            return scheme == .light
                ? WidgetRGB(red: 0.965, green: 0.965, blue: 0.965)
                : WidgetRGB(red: 0.14, green: 0.14, blue: 0.14)
        case .light:
            return WidgetRGB(red: 0.965, green: 0.97, blue: 0.98)
        case .dark:
            return WidgetRGB(red: 0.105, green: 0.115, blue: 0.14)
        case .midnight:
            return WidgetRGB(red: 0.025, green: 0.045, blue: 0.09)
        case .neutral:
            return scheme == .light
                ? WidgetRGB(red: 0.91, green: 0.91, blue: 0.92)
                : WidgetRGB(red: 0.19, green: 0.19, blue: 0.2)
        case .providerTinted:
            let baseline = scheme == .light
                ? WidgetRGB(red: 0.97, green: 0.97, blue: 0.97)
                : WidgetRGB(red: 0.12, green: 0.12, blue: 0.12)
            return baseline.mixed(with: providerBaseAccent, amount: 0.105)
        }
    }
}

extension Color {
    init(widgetRGB value: WidgetRGB) {
        self.init(
            red: value.red,
            green: value.green,
            blue: value.blue
        )
    }
}
