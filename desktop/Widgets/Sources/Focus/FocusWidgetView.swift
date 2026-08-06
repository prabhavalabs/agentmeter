import AgentMeterWidgetCore
import SwiftUI

enum FocusHistoryPlacement: Hashable {
    case hidden
    case compactBelow
    case below
    case beside
}

enum FocusHistoryEmphasis: Hashable {
    case hidden
    case compact
    case balanced
    case expanded
}

struct FocusLayoutPlan: Hashable {
    let ringSize: CGFloat
    let spacing: CGFloat
    let padding: CGFloat
    let historyPlacement: FocusHistoryPlacement
    let historyEmphasis: FocusHistoryEmphasis
    let historyHeight: CGFloat
    let additionalWindowLimit: Int
    let mediumPrimaryContentHeight: CGFloat?
    let mediumRequiredHeight: CGFloat?
    let usesCompactHeader: Bool
    let usesCompactResetSummaries: Bool
    let showsHealthyMetadata: Bool

    init(presentation: WidgetPresentation) {
        let hasHistory = presentation.family != .small
            && presentation.modules.contains(.history)
            && presentation.history != nil
        let compactDensity = presentation.configuration.density == .compact

        let base: (ring: CGFloat, spacing: CGFloat, padding: CGFloat)
        switch presentation.family {
        case .small:
            base = (66, 4, 10)
            historyPlacement = .hidden
            showsHealthyMetadata = false
        case .medium:
            base = (78, 5, 8)
            historyPlacement = hasHistory ? .compactBelow : .hidden
            showsHealthyMetadata = false
        case .large:
            base = (128, 10, 14)
            historyPlacement = hasHistory
                ? (presentation.configuration.layout == .expanded ? .beside : .below)
                : .hidden
            showsHealthyMetadata = true
        case .extraLarge:
            base = (150, 12, 16)
            historyPlacement = hasHistory ? .beside : .hidden
            showsHealthyMetadata = true
        }
        additionalWindowLimit = FocusWindowCapacity.additionalLimit(for: presentation.family)

        let layoutAdjustment: (ring: CGFloat, spacing: CGFloat, padding: CGFloat)
        let requestedCompactHeader: Bool
        let requestedCompactResetSummaries: Bool
        switch presentation.configuration.layout {
        case .automatic:
            layoutAdjustment = (0, 0, 0)
            historyEmphasis = hasHistory ? .balanced : .hidden
            requestedCompactHeader = false
            requestedCompactResetSummaries = presentation.family == .small || presentation.family == .medium
        case .usageAndRings:
            layoutAdjustment = (12, 1, 0)
            historyEmphasis = hasHistory ? .compact : .hidden
            requestedCompactHeader = false
            requestedCompactResetSummaries = true
        case .compact:
            layoutAdjustment = (-10, -2, -2)
            historyEmphasis = hasHistory ? .compact : .hidden
            requestedCompactHeader = true
            requestedCompactResetSummaries = true
        case .expanded:
            layoutAdjustment = (6, 2, 2)
            historyEmphasis = hasHistory ? .expanded : .hidden
            requestedCompactHeader = false
            requestedCompactResetSummaries = false
        }

        ringSize = max(62, base.ring + layoutAdjustment.ring - (compactDensity ? 6 : 0))
        spacing = max(2, base.spacing + layoutAdjustment.spacing - (compactDensity ? 2 : 0))
        padding = max(6, base.padding + layoutAdjustment.padding - (compactDensity ? 2 : 0))
        usesCompactHeader = presentation.family == .medium ? true : requestedCompactHeader
        usesCompactResetSummaries = presentation.family == .medium
            ? true
            : requestedCompactResetSummaries

        switch presentation.family {
        case .small:
            historyHeight = 0
        case .medium:
            historyHeight = switch historyEmphasis {
            case .hidden: 0
            case .compact: 20
            case .balanced: 22
            case .expanded: 24
            }
        case .large, .extraLarge:
            historyHeight = switch historyEmphasis {
            case .hidden: 0
            case .compact: 78
            case .balanced: 104
            case .expanded: 132
            }
        }

        if presentation.family == .medium {
            let primaryHeight = max(ringSize, 116)
            mediumPrimaryContentHeight = primaryHeight
            mediumRequiredHeight = (padding * 2)
                + primaryHeight
                + (hasHistory ? min(spacing, 6) + historyHeight : 0)
        } else {
            mediumPrimaryContentHeight = nil
            mediumRequiredHeight = nil
        }
    }
}

struct FocusWidgetSemantics: Equatable {
    let showsHistory: Bool
    let additionalWindowLimit: Int
    let additionalOverflowCount: Int
    let additionalOverflowLabel: String?

    init(presentation: WidgetPresentation) {
        showsHistory = presentation.family != .small
            && presentation.modules.contains(.history)
            && presentation.history != nil
        additionalWindowLimit = FocusWindowCapacity.additionalLimit(for: presentation.family)
        let reportedCount = presentation.providers.first?.additionalWindows.count ?? 0
        additionalOverflowCount = presentation.family == .small
            ? 0
            : max(0, reportedCount - additionalWindowLimit)
        additionalOverflowLabel = additionalOverflowCount > 0 ? "+\(additionalOverflowCount)" : nil
    }
}

enum FocusProviderAccessibility {
    static func summary(
        _ provider: WidgetProviderPresentation,
        freshness: WidgetFreshnessState,
        modules: Set<WidgetModule>,
        showsHealthyMetadata: Bool
    ) -> String {
        var parts = [provider.name]
        if showsHealthyMetadata, modules.contains(.status), provider.healthState == .healthy {
            parts.append("Status \(provider.status)")
        }
        if showsHealthyMetadata, modules.contains(.freshness), freshness == .fresh {
            parts.append("Freshness Current")
        }
        parts.append(contentsOf: WidgetHealthSemantics.mandatoryLabels(
            provider: provider,
            freshness: freshness
        ))
        return parts.joined(separator: ", ")
    }
}

struct FocusWidgetView: View {
    let presentation: WidgetPresentation
    @Environment(\.colorScheme) private var colorScheme

    private var provider: WidgetProviderPresentation? { presentation.providers.first }
    private var layoutPlan: FocusLayoutPlan { FocusLayoutPlan(presentation: presentation) }
    private var semantics: FocusWidgetSemantics { FocusWidgetSemantics(presentation: presentation) }
    private var palette: WidgetThemePalette {
        WidgetThemePalette(
            theme: presentation.configuration.theme,
            providerID: provider?.id ?? "",
            colorScheme: colorScheme
        )
    }

    var providerHealthLabels: [String] {
        guard let provider else { return [] }
        return WidgetHealthSemantics.mandatoryLabels(
            provider: provider,
            freshness: presentation.freshness
        )
    }

    var body: some View {
        Group {
            if let provider {
                if let outer = provider.rings.first {
                    focusContent(provider: provider, outer: outer)
                } else {
                    unavailableUsage(provider: provider)
                }
            } else {
                WidgetStateView(title: "Provider unavailable", systemImage: "person.crop.circle.badge.questionmark")
                    .padding()
            }
        }
        .foregroundStyle(palette.primaryText)
        .containerBackground(for: .widget) {
            palette.background
        }
        .preferredColorScheme(palette.preferredColorScheme)
        .widgetURL(destinationURL)
        .privacySensitive()
    }

    private func unavailableUsage(provider: WidgetProviderPresentation) -> some View {
        VStack(alignment: .leading, spacing: layoutPlan.spacing) {
            providerHeader(
                provider,
                compact: presentation.family == .small || presentation.family == .medium
            )
            WidgetStateView(
                title: "Allowance unavailable",
                systemImage: "gauge.with.dots.needle.0percent"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(layoutPlan.padding)
    }

    @ViewBuilder
    private func focusContent(
        provider: WidgetProviderPresentation,
        outer: WidgetRingPresentation
    ) -> some View {
        switch presentation.family {
        case .small:
            smallLayout(provider: provider, outer: outer)
        case .medium:
            mediumLayout(provider: provider, outer: outer)
        case .large:
            largeLayout(provider: provider, outer: outer)
        case .extraLarge:
            extraLargeLayout(provider: provider, outer: outer)
        }
    }

    private func smallLayout(
        provider: WidgetProviderPresentation,
        outer: WidgetRingPresentation
    ) -> some View {
        VStack(spacing: layoutPlan.spacing) {
            providerHeader(provider, compact: true)
            DualUsageRing(
                outer: outer,
                inner: provider.rings.dropFirst().first,
                outerAccent: palette.dataAccent(.outerRing),
                innerAccent: palette.dataAccent(.innerRing),
                percentageMode: presentation.configuration.percentageMode,
                track: palette.track
            )
            .frame(maxHeight: layoutPlan.ringSize)

            HStack(alignment: .top, spacing: 7) {
                resetSummary(outer, compact: true)
                if let inner = provider.rings.dropFirst().first {
                    Divider()
                    resetSummary(inner, compact: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(layoutPlan.padding)
    }

    private func mediumLayout(
        provider: WidgetProviderPresentation,
        outer: WidgetRingPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: min(layoutPlan.spacing, 6)) {
            HStack(spacing: layoutPlan.spacing + 4) {
                DualUsageRing(
                    outer: outer,
                    inner: provider.rings.dropFirst().first,
                    outerAccent: palette.dataAccent(.outerRing),
                    innerAccent: palette.dataAccent(.innerRing),
                    percentageMode: presentation.configuration.percentageMode,
                    track: palette.track
                )
                .frame(width: layoutPlan.ringSize, height: layoutPlan.ringSize)

                VStack(alignment: .leading, spacing: 3) {
                    providerHeader(provider, compact: true)
                    HStack(alignment: .top, spacing: 10) {
                        resetSummary(outer, compact: true)
                        if let inner = provider.rings.dropFirst().first {
                            resetSummary(inner, compact: true)
                        }
                    }
                    additionalRows(
                        provider.additionalWindows,
                        limit: layoutPlan.additionalWindowLimit
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: layoutPlan.mediumPrimaryContentHeight)

            if semantics.showsHistory {
                historyView(compact: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: layoutPlan.historyHeight)
            }
        }
        .padding(layoutPlan.padding)
    }

    private func largeLayout(
        provider: WidgetProviderPresentation,
        outer: WidgetRingPresentation
    ) -> some View {
        Group {
            if layoutPlan.historyPlacement == .beside {
                HStack(spacing: layoutPlan.spacing + 6) {
                    VStack(alignment: .leading, spacing: layoutPlan.spacing) {
                        providerHeader(provider, compact: layoutPlan.usesCompactHeader)
                        focusUsageBlock(provider: provider, outer: outer)
                        metadata(provider)
                    }
                    .frame(maxWidth: 176, alignment: .leading)
                    if semantics.showsHistory {
                        Divider()
                        historyView(compact: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: layoutPlan.spacing) {
                    providerHeader(provider, compact: layoutPlan.usesCompactHeader)
                    focusUsageBlock(provider: provider, outer: outer)
                    if semantics.showsHistory {
                        historyView(compact: layoutPlan.historyEmphasis == .compact)
                            .frame(maxWidth: .infinity)
                            .frame(height: layoutPlan.historyHeight)
                    }
                    metadata(provider)
                }
            }
        }
        .padding(layoutPlan.padding)
    }

    private func extraLargeLayout(
        provider: WidgetProviderPresentation,
        outer: WidgetRingPresentation
    ) -> some View {
        Group {
            if semantics.showsHistory {
                HStack(spacing: layoutPlan.spacing + 8) {
                    extraLargeUsagePanel(provider: provider, outer: outer)
                        .frame(maxWidth: 290, alignment: .leading)
                    Divider()
                    historyView(compact: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                extraLargeUsagePanel(provider: provider, outer: outer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(layoutPlan.padding)
    }

    private func extraLargeUsagePanel(
        provider: WidgetProviderPresentation,
        outer: WidgetRingPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: layoutPlan.spacing) {
            providerHeader(provider, compact: layoutPlan.usesCompactHeader)
            HStack(spacing: layoutPlan.spacing + 4) {
                DualUsageRing(
                    outer: outer,
                    inner: provider.rings.dropFirst().first,
                    outerAccent: palette.dataAccent(.outerRing),
                    innerAccent: palette.dataAccent(.innerRing),
                    percentageMode: presentation.configuration.percentageMode,
                    track: palette.track
                )
                .frame(width: layoutPlan.ringSize, height: layoutPlan.ringSize)
                VStack(alignment: .leading, spacing: layoutPlan.spacing) {
                    resetSummary(outer, compact: layoutPlan.usesCompactResetSummaries)
                    if let inner = provider.rings.dropFirst().first {
                        resetSummary(inner, compact: layoutPlan.usesCompactResetSummaries)
                    }
                }
            }
            additionalRows(
                provider.additionalWindows,
                limit: layoutPlan.additionalWindowLimit
            )
            metadata(provider)
        }
    }

    private func providerHeader(
        _ provider: WidgetProviderPresentation,
        compact: Bool
    ) -> some View {
        HStack(spacing: compact ? 6 : 9) {
            WidgetProviderMark(
                providerID: provider.id,
                name: provider.name,
                accent: palette.dataAccent(.providerMark),
                size: compact ? 23 : 32
            )
            VStack(alignment: .leading, spacing: 0) {
                Text(provider.name)
                    .font(compact ? .caption.weight(.bold) : .headline)
                    .lineLimit(1)
                if compact == false {
                    Text(presentation.configuration.percentageMode == .used ? "Allowance used" : "Allowance remaining")
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            Spacer(minLength: 0)
            WidgetHealthBadges(
                labels: WidgetHealthSemantics.mandatoryLabels(
                    provider: provider,
                    freshness: presentation.freshness
                ),
                compact: compact
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FocusProviderAccessibility.summary(
            provider,
            freshness: presentation.freshness,
            modules: presentation.modules,
            showsHealthyMetadata: layoutPlan.showsHealthyMetadata
        ))
    }

    @ViewBuilder
    private func focusUsageBlock(
        provider: WidgetProviderPresentation,
        outer: WidgetRingPresentation
    ) -> some View {
        if layoutPlan.historyPlacement == .beside {
            VStack(alignment: .leading, spacing: layoutPlan.spacing) {
                DualUsageRing(
                    outer: outer,
                    inner: provider.rings.dropFirst().first,
                    outerAccent: palette.dataAccent(.outerRing),
                    innerAccent: palette.dataAccent(.innerRing),
                    percentageMode: presentation.configuration.percentageMode,
                    track: palette.track
                )
                .frame(
                    width: min(layoutPlan.ringSize, 112),
                    height: min(layoutPlan.ringSize, 112)
                )
                HStack(alignment: .top, spacing: layoutPlan.spacing) {
                    resetSummary(outer, compact: layoutPlan.usesCompactResetSummaries)
                    if let inner = provider.rings.dropFirst().first {
                        resetSummary(inner, compact: layoutPlan.usesCompactResetSummaries)
                    }
                }
                additionalRows(
                    provider.additionalWindows,
                    limit: layoutPlan.additionalWindowLimit
                )
            }
        } else {
            HStack(alignment: .center, spacing: layoutPlan.spacing + 6) {
                DualUsageRing(
                    outer: outer,
                    inner: provider.rings.dropFirst().first,
                    outerAccent: palette.dataAccent(.outerRing),
                    innerAccent: palette.dataAccent(.innerRing),
                    percentageMode: presentation.configuration.percentageMode,
                    track: palette.track
                )
                .frame(width: layoutPlan.ringSize, height: layoutPlan.ringSize)

                VStack(alignment: .leading, spacing: layoutPlan.spacing) {
                    resetSummary(outer, compact: layoutPlan.usesCompactResetSummaries)
                    if let inner = provider.rings.dropFirst().first {
                        resetSummary(inner, compact: layoutPlan.usesCompactResetSummaries)
                    }
                    additionalRows(
                        provider.additionalWindows,
                        limit: layoutPlan.additionalWindowLimit
                    )
                }
            }
        }
    }

    private func resetSummary(
        _ ring: WidgetRingPresentation,
        compact: Bool
    ) -> some View {
        ResetSummary(
            presentation: ring,
            showsCountdown: presentation.configuration.showsResetCountdown,
            showsAbsoluteDate: presentation.configuration.showsAbsoluteResetDate,
            compact: compact
        )
    }

    @ViewBuilder
    private func additionalRows(
        _ rows: [WidgetRingPresentation],
        limit: Int
    ) -> some View {
        ForEach(Array(rows.prefix(limit).enumerated()), id: \.element.windowKind) { _, row in
            HStack(spacing: 6) {
                Text(row.label)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(row.displayedPercent.map { "\($0)%" } ?? "Not reported")
                    .monospacedDigit()
                    .foregroundStyle(row.displayedPercent == nil ? palette.secondaryText : palette.primaryText)
                resetStateSymbol(row.resetState)
            }
            .font(.caption)
            .accessibilityElement(children: .combine)
        }
        let overflowCount = max(0, rows.count - limit)
        if overflowCount > 0 {
            Text("+\(overflowCount) more windows")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.secondaryText)
                .accessibilityLabel("\(overflowCount) more allowance windows")
        }
    }

    @ViewBuilder
    private func resetStateSymbol(_ state: WidgetResetState) -> some View {
        switch state {
        case .unavailable:
            Image(systemName: "questionmark.circle")
                .accessibilityLabel("Reset time unavailable")
        case .pending:
            Image(systemName: "arrow.clockwise")
                .accessibilityLabel("Refresh pending")
        case .scheduled:
            Image(systemName: "clock")
                .accessibilityLabel("Reset scheduled")
        }
    }

    @ViewBuilder
    private func historyView(compact: Bool) -> some View {
        if presentation.modules.contains(.history), let history = presentation.history {
            if let message = history.availabilityMessage {
                if compact {
                    Label(message, systemImage: "calendar.badge.exclamationmark")
                        .font(.caption2)
                        .lineLimit(2)
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityLabel(message)
                } else {
                    WidgetStateView(title: message, systemImage: "calendar.badge.exclamationmark")
                }
            } else {
                switch presentation.configuration.historyStyle {
                case .heatMap, .bars:
                    UsageHeatMap(
                        projection: history,
                        lowAccent: palette.dataAccent(.heatLow),
                        moderateAccent: palette.dataAccent(.heatModerate),
                        highAccent: palette.dataAccent(.heatHigh),
                        veryHighAccent: palette.dataAccent(.heatVeryHigh),
                        showsHeader: compact == false,
                        compact: compact
                    )
                case .trend:
                    UsageTrendChart(
                        projection: history,
                        lineAccent: palette.dataAccent(.trendLine),
                        pointAccent: palette.dataAccent(.trendPoint),
                        showsHeader: compact == false
                    )
                case .none:
                    EmptyView()
                }
            }
        }
    }

    private func metadata(_ provider: WidgetProviderPresentation) -> some View {
        Group {
            if layoutPlan.showsHealthyMetadata {
                HStack(spacing: 10) {
                    if presentation.modules.contains(.status), provider.healthState == .healthy {
                        Label(provider.status, systemImage: "circle.fill")
                            .lineLimit(1)
                    }
                    if presentation.modules.contains(.freshness), presentation.freshness == .fresh {
                        Label("Current", systemImage: "checkmark.circle")
                    }
                }
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var destinationURL: URL {
        switch presentation.configuration.tapDestination {
        case .overview:
            return AgentMeterRoute.overview.url
        case .agents:
            return AgentMeterRoute.agents.url
        case .providerDetail:
            guard let providerID = provider?.id, AgentMeterRoute.isValidProviderID(providerID) else {
                return AgentMeterRoute.overview.url
            }
            return AgentMeterRoute.provider(providerID).url
        }
    }
}
