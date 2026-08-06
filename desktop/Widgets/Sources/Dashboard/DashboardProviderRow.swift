import AgentMeterWidgetCore
import SwiftUI

enum DashboardProviderRowStyle: Hashable {
    case outerOnly
    case dualCompact
    case detailed
    case expanded
    case analyticsCompact
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

    static func accessiblePercentage(
        _ ring: WidgetRingPresentation,
        mode: WidgetPercentageMode
    ) -> String {
        guard let percent = ring.displayedPercent else { return "Not reported" }
        let modeLabel = mode == .used ? "used" : "remaining"
        return "\(percent) percent \(modeLabel)"
    }
}

struct DashboardResetPresentation: Equatable {
    let lines: [String]

    init(
        ring: WidgetRingPresentation,
        showsCountdown: Bool,
        showsAbsoluteDate: Bool,
        relativeTo referenceDate: Date = .now
    ) {
        guard case let .scheduled(epoch) = ring.resetState else {
            lines = [DashboardProviderCopy.reset(ring)]
            return
        }

        let resetDate = Date(timeIntervalSince1970: TimeInterval(epoch))
        var scheduledLines: [String] = []
        if showsCountdown {
            scheduledLines.append("Reset countdown \(Self.countdown(from: referenceDate, to: resetDate))")
        }
        if showsAbsoluteDate {
            scheduledLines.append(
                "Reset date \(resetDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
            )
        }
        lines = scheduledLines.isEmpty ? ["Reset scheduled"] : scheduledLines
    }

    private static func countdown(from referenceDate: Date, to resetDate: Date) -> String {
        let seconds = Int(resetDate.timeIntervalSince(referenceDate).rounded())
        let magnitude = abs(seconds)
        let value: Int
        let unit: String

        if magnitude >= 86_400 {
            value = max(1, magnitude / 86_400)
            unit = value == 1 ? "day" : "days"
        } else if magnitude >= 3_600 {
            value = max(1, magnitude / 3_600)
            unit = value == 1 ? "hour" : "hours"
        } else if magnitude >= 60 {
            value = max(1, magnitude / 60)
            unit = value == 1 ? "minute" : "minutes"
        } else {
            value = magnitude
            unit = value == 1 ? "second" : "seconds"
        }

        return seconds >= 0 ? "in \(value) \(unit)" : "\(value) \(unit) ago"
    }
}

enum DashboardProviderAccessibility {
    static func summary(
        _ provider: WidgetProviderPresentation,
        percentageMode: WidgetPercentageMode,
        style: DashboardProviderRowStyle,
        additionalWindowLimit: Int,
        modules: Set<WidgetModule>,
        freshness: WidgetFreshnessState,
        showsMetadata: Bool,
        showsResetCountdown: Bool,
        showsAbsoluteResetDate: Bool,
        relativeTo referenceDate: Date = .now
    ) -> String {
        var visibleWindows = Array(provider.rings.prefix(style == .outerOnly ? 1 : 2))
        if style == .expanded || style == .analyticsCompact {
            visibleWindows.append(contentsOf: provider.additionalWindows.prefix(additionalWindowLimit))
        }

        let rings = visibleWindows.map { ring in
            let reset = DashboardResetPresentation(
                ring: ring,
                showsCountdown: showsResetCountdown,
                showsAbsoluteDate: showsAbsoluteResetDate,
                relativeTo: referenceDate
            ).lines.joined(separator: ", ")
            return "\(ring.label), \(DashboardProviderCopy.accessiblePercentage(ring, mode: percentageMode)), \(reset)"
        }
        var parts = [
            provider.name,
            "Percentage mode \(percentageMode == .used ? "Used" : "Remaining")",
        ] + rings
        if showsMetadata, modules.contains(.status) {
            parts.append("Status \(provider.status)")
        }
        if showsMetadata, modules.contains(.freshness) {
            parts.append("Freshness \(freshness == .fresh ? "Current" : "Stale")")
        }
        return parts.joined(separator: ", ")
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
    let showsMetadata: Bool

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
        additionalWindowLimit: Int = 0,
        showsMetadata: Bool = false
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
        self.showsMetadata = showsMetadata
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
                            resetDetails(outer)
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

                if style == .expanded || style == .analyticsCompact {
                    ForEach(Array(provider.additionalWindows.prefix(additionalWindowLimit)), id: \.windowKind) { window in
                        ringLine(window, includesReset: false)
                    }
                }

                if showsMetadata {
                    metadata
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(palette.primaryText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DashboardProviderAccessibility.summary(
            provider,
            percentageMode: percentageMode,
            style: style,
            additionalWindowLimit: additionalWindowLimit,
            modules: modules,
            freshness: freshness,
            showsMetadata: showsMetadata,
            showsResetCountdown: showsResetCountdown,
            showsAbsoluteResetDate: showsAbsoluteResetDate
        ))
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
                resetDetails(ring)
            }
        }
        .font(.caption2)
    }

    private func resetDetails(_ ring: WidgetRingPresentation) -> some View {
        let presentation = DashboardResetPresentation(
            ring: ring,
            showsCountdown: showsResetCountdown,
            showsAbsoluteDate: showsAbsoluteResetDate
        )
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(presentation.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(palette.secondaryText)
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
    private var markSize: CGFloat { style == .outerOnly ? 21 : 24 }
    private var ringSize: CGFloat { style == .expanded ? 42 : 34 }
    private var nameFont: Font { style == .outerOnly ? .caption.weight(.semibold) : .caption.weight(.bold) }
}
