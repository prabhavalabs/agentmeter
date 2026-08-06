import AgentMeterWidgetCore
import SwiftUI

enum DashboardProviderRowStyle {
    case outerOnly
    case dualCompact
    case detailed
    case expanded
}

enum DashboardProviderCopy {
    static func percentage(_ ring: WidgetRingPresentation) -> String {
        ring.displayedPercent.map { "\($0)%" } ?? "Not reported"
    }

    static func reset(_ ring: WidgetRingPresentation) -> String {
        switch ring.resetState {
        case .unavailable: "Reset time unavailable"
        case .pending: "Refresh pending"
        case .scheduled: "Reset scheduled"
        }
    }
}

enum DashboardProviderAccessibility {
    static func summary(_ provider: WidgetProviderPresentation) -> String {
        let rings = provider.rings.map {
            "\($0.label), \(DashboardProviderCopy.percentage($0)), \(DashboardProviderCopy.reset($0))"
        }
        return ([provider.name] + rings).joined(separator: ", ")
    }
}

struct DashboardProviderRow: View {
    let provider: WidgetProviderPresentation
    let percentageMode: WidgetPercentageMode
    let modules: Set<WidgetModule>
    let freshness: WidgetFreshnessState
    let showsResetCountdown: Bool
    let showsAbsoluteResetDate: Bool
    let style: DashboardProviderRowStyle
    let additionalWindowLimit: Int

    @Environment(\.colorScheme) private var colorScheme

    private var palette: WidgetThemePalette {
        WidgetThemePalette(theme: theme, providerID: provider.id, colorScheme: colorScheme)
    }

    private let theme: WidgetTheme

    init(
        provider: WidgetProviderPresentation,
        percentageMode: WidgetPercentageMode,
        modules: Set<WidgetModule>,
        freshness: WidgetFreshnessState,
        showsResetCountdown: Bool,
        showsAbsoluteResetDate: Bool,
        theme: WidgetTheme,
        style: DashboardProviderRowStyle,
        additionalWindowLimit: Int = 0
    ) {
        self.provider = provider
        self.percentageMode = percentageMode
        self.modules = modules
        self.freshness = freshness
        self.showsResetCountdown = showsResetCountdown
        self.showsAbsoluteResetDate = showsAbsoluteResetDate
        self.theme = theme
        self.style = style
        self.additionalWindowLimit = additionalWindowLimit
    }

    var body: some View {
        HStack(spacing: rowSpacing) {
            WidgetProviderMark(
                providerID: provider.id,
                name: provider.name,
                accent: palette.dataAccent(.providerMark),
                size: markSize
            )

            if style == .dualCompact || style == .expanded, let outer = provider.rings.first {
                DualUsageRing(
                    outer: outer,
                    inner: provider.rings.dropFirst().first,
                    outerAccent: palette.dataAccent(.outerRing),
                    innerAccent: palette.dataAccent(.innerRing),
                    percentageMode: percentageMode,
                    track: palette.track
                )
                .frame(width: ringSize, height: ringSize)
                .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: style == .outerOnly ? 1 : 2) {
                HStack(spacing: 4) {
                    Text(provider.name)
                        .font(nameFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 2)
                    if style == .outerOnly, let outer = provider.rings.first {
                        Text(DashboardProviderCopy.percentage(outer))
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                    }
                }

                if let outer = provider.rings.first {
                    if style == .outerOnly {
                        HStack(spacing: 4) {
                            Text(outer.label)
                                .lineLimit(1)
                            Text(resetDisplay(outer))
                                .lineLimit(1)
                                .foregroundStyle(palette.secondaryText)
                        }
                        .font(.caption2)
                    } else {
                        ringLine(outer, includesReset: true)
                    }
                } else {
                    Text("Allowance unavailable")
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                }

                if style != .outerOnly, let inner = provider.rings.dropFirst().first {
                    ringLine(inner, includesReset: style != .dualCompact)
                }

                if style == .expanded {
                    ForEach(Array(provider.additionalWindows.prefix(additionalWindowLimit)), id: \.windowKind) { window in
                        ringLine(window, includesReset: false)
                    }
                }

                if style == .detailed || style == .expanded {
                    metadata
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(palette.primaryText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DashboardProviderAccessibility.summary(provider))
    }

    private func ringLine(
        _ ring: WidgetRingPresentation,
        includesReset: Bool
    ) -> some View {
        HStack(spacing: 4) {
            Text(ring.label)
                .lineLimit(1)
            Text(DashboardProviderCopy.percentage(ring))
                .monospacedDigit()
                .foregroundStyle(ring.displayedPercent == nil ? palette.secondaryText : palette.primaryText)
            if includesReset {
                Text(resetDisplay(ring))
                    .lineLimit(1)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .font(.caption2)
    }

    private func resetDisplay(_ ring: WidgetRingPresentation) -> String {
        guard case let .scheduled(epoch) = ring.resetState else {
            return DashboardProviderCopy.reset(ring)
        }
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        if showsAbsoluteResetDate {
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        if showsResetCountdown {
            return date.formatted(.relative(presentation: .numeric))
        }
        return "Reset scheduled"
    }

    @ViewBuilder
    private var metadata: some View {
        HStack(spacing: 7) {
            if modules.contains(.status) {
                Text(provider.status)
                    .lineLimit(1)
            }
            if modules.contains(.freshness) {
                Text(freshness == .fresh ? "Current" : "Stale")
            }
        }
        .font(.caption2)
        .foregroundStyle(palette.secondaryText)
    }

    private var rowSpacing: CGFloat { style == .outerOnly ? 6 : 8 }
    private var markSize: CGFloat { style == .outerOnly ? 20 : 24 }
    private var ringSize: CGFloat { style == .expanded ? 42 : 34 }
    private var nameFont: Font { style == .outerOnly ? .caption.weight(.semibold) : .caption.weight(.bold) }
}
