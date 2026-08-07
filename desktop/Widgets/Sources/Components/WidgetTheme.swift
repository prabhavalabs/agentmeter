import AgentMeterCore
import AgentMeterWidgetCore
import SwiftUI

/// Fixed tokens from the approved "AgentMeter Widgets v2" design language.
enum WidgetV2Tokens {
    static let cardTop = Color(red: 0x23 / 255, green: 0x23 / 255, blue: 0x27 / 255)
    static let cardBottom = Color(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1B / 255)
    static let live = Color(red: 0x3D / 255, green: 0xDC / 255, blue: 0x97 / 255)
    static let warn = Color(red: 0xFB / 255, green: 0xBF / 255, blue: 0x24 / 255)

    static var cardGradient: LinearGradient {
        LinearGradient(
            colors: [cardTop, cardBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct WidgetThemePalette {
    let background: Color
    let primaryText: Color
    let secondaryText: Color
    /// The 45%-strength caption tier from the v2 language.
    let tertiaryText: Color
    let track: Color
    /// 1 pt module divider.
    let rule: Color
    /// Card outline.
    let border: Color
    /// XL mini-card fill and outline.
    let chipFill: Color
    let chipBorder: Color
    let dataAccents: WidgetDataAccentPalette
    let preferredColorScheme: ColorScheme?
    private let usesCardGradient: Bool

    init(theme: WidgetTheme, providerID: String, colorScheme: ColorScheme) {
        let providerBaseRGB = WidgetRGB(hex: ProviderVisuals.accentHex(for: providerID))
        dataAccents = WidgetThemeContrastModel.dataAccents(
            theme: theme,
            requestedScheme: colorScheme,
            providerBaseAccent: providerBaseRGB
        )
        let providerBaseAccent = Color(widgetRGB: providerBaseRGB)

        switch theme {
        case .system:
            background = Color.primary.opacity(0.035)
            primaryText = .primary
            secondaryText = .secondary
            tertiaryText = Color.secondary.opacity(0.75)
            track = Color.secondary.opacity(0.18)
            rule = Color.secondary.opacity(0.16)
            border = Color.secondary.opacity(0.14)
            chipFill = Color.primary.opacity(0.035)
            chipBorder = Color.primary.opacity(0.05)
            preferredColorScheme = nil
            usesCardGradient = false
        case .light:
            background = Color(red: 0.965, green: 0.97, blue: 0.98)
            primaryText = Color(red: 0.08, green: 0.09, blue: 0.12)
            secondaryText = Color(red: 0.32, green: 0.34, blue: 0.4)
            tertiaryText = Color(red: 0.45, green: 0.47, blue: 0.52)
            track = Color.black.opacity(0.12)
            rule = Color.black.opacity(0.08)
            border = Color.black.opacity(0.09)
            chipFill = Color.black.opacity(0.035)
            chipBorder = Color.black.opacity(0.05)
            preferredColorScheme = .light
            usesCardGradient = false
        case .dark:
            background = WidgetV2Tokens.cardBottom
            primaryText = .white
            secondaryText = Color.white.opacity(0.65)
            tertiaryText = Color.white.opacity(0.45)
            track = Color.white.opacity(0.08)
            rule = Color.white.opacity(0.07)
            border = Color.white.opacity(0.09)
            chipFill = Color.white.opacity(0.035)
            chipBorder = Color.white.opacity(0.05)
            preferredColorScheme = .dark
            usesCardGradient = true
        case .midnight:
            background = Color(red: 0.025, green: 0.045, blue: 0.09)
            primaryText = Color(red: 0.9, green: 0.95, blue: 1)
            secondaryText = Color(red: 0.62, green: 0.72, blue: 0.84)
            tertiaryText = Color(red: 0.5, green: 0.6, blue: 0.72)
            track = Color.white.opacity(0.12)
            rule = Color.white.opacity(0.08)
            border = Color.white.opacity(0.1)
            chipFill = Color.white.opacity(0.04)
            chipBorder = Color.white.opacity(0.06)
            preferredColorScheme = .dark
            usesCardGradient = false
        case .neutral:
            background = Color.secondary.opacity(0.08)
            primaryText = .primary
            secondaryText = .secondary
            tertiaryText = Color.secondary.opacity(0.75)
            track = Color.secondary.opacity(0.2)
            rule = Color.secondary.opacity(0.16)
            border = Color.secondary.opacity(0.14)
            chipFill = Color.primary.opacity(0.035)
            chipBorder = Color.primary.opacity(0.05)
            preferredColorScheme = nil
            usesCardGradient = false
        case .providerTinted:
            background = providerBaseAccent.opacity(0.105)
            primaryText = .primary
            secondaryText = .secondary
            tertiaryText = Color.secondary.opacity(0.75)
            track = Color.secondary.opacity(0.2)
            rule = Color.secondary.opacity(0.16)
            border = Color.secondary.opacity(0.14)
            chipFill = Color.primary.opacity(0.035)
            chipBorder = Color.primary.opacity(0.05)
            preferredColorScheme = nil
            usesCardGradient = false
        }
    }

    /// Container fill for the widget card — the v2 gradient on the dark
    /// theme, a flat colour elsewhere.
    var cardFill: AnyShapeStyle {
        usesCardGradient
            ? AnyShapeStyle(WidgetV2Tokens.cardGradient)
            : AnyShapeStyle(background)
    }

    func dataAccent(_ role: WidgetDataAccentRole) -> Color {
        Color(widgetRGB: dataAccents[role])
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

enum WidgetDataAccentRole: CaseIterable, Sendable {
    case outerRing
    case innerRing
    case heatLow
    case heatModerate
    case heatHigh
    case heatVeryHigh
    case trendLine
    case trendPoint
    case providerMark
}

struct WidgetDataAccentPalette: Sendable {
    private let opaqueAccent: WidgetRGB

    init(opaqueAccent: WidgetRGB) {
        self.opaqueAccent = opaqueAccent
    }

    subscript(role: WidgetDataAccentRole) -> WidgetRGB {
        switch role {
        case .outerRing,
             .innerRing,
             .heatLow,
             .heatModerate,
             .heatHigh,
             .heatVeryHigh,
             .trendLine,
             .trendPoint,
             .providerMark:
            opaqueAccent
        }
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
    static func dataAccents(
        theme: WidgetTheme,
        requestedScheme: ColorScheme,
        providerBaseAccent: WidgetRGB
    ) -> WidgetDataAccentPalette {
        let background = background(
            theme: theme,
            requestedScheme: requestedScheme,
            providerBaseAccent: providerBaseAccent
        )
        let resolved = WidgetAccentResolver.resolve(
            base: providerBaseAccent,
            against: background,
            scheme: effectiveScheme(theme: theme, requestedScheme: requestedScheme)
        )
        return WidgetDataAccentPalette(opaqueAccent: resolved)
    }

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
