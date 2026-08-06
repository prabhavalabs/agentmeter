import AgentMeterWidgetCore
import SwiftUI

struct FocusWidgetView: View {
    let presentation: WidgetPresentation
    @Environment(\.colorScheme) private var colorScheme

    private var provider: WidgetProviderPresentation? { presentation.providers.first }
    private var palette: WidgetThemePalette {
        WidgetThemePalette(
            theme: presentation.configuration.theme,
            providerID: provider?.id ?? "",
            colorScheme: colorScheme
        )
    }

    var body: some View {
        Group {
            if let provider, let outer = provider.rings.first {
                focusContent(provider: provider, outer: outer)
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
        VStack(spacing: 4) {
            providerHeader(provider, compact: true)
            DualUsageRing(
                outer: outer,
                inner: provider.rings.dropFirst().first,
                outerAccent: palette.dataAccent(.outerRing),
                innerAccent: palette.dataAccent(.innerRing),
                percentageMode: presentation.configuration.percentageMode,
                track: palette.track
            )
            .frame(maxHeight: 78)

            HStack(alignment: .top, spacing: 7) {
                resetSummary(outer, compact: true)
                if let inner = provider.rings.dropFirst().first {
                    Divider()
                    resetSummary(inner, compact: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
    }

    private func mediumLayout(
        provider: WidgetProviderPresentation,
        outer: WidgetRingPresentation
    ) -> some View {
        HStack(spacing: 13) {
            DualUsageRing(
                outer: outer,
                inner: provider.rings.dropFirst().first,
                outerAccent: palette.dataAccent(.outerRing),
                innerAccent: palette.dataAccent(.innerRing),
                percentageMode: presentation.configuration.percentageMode,
                track: palette.track
            )
            .frame(width: 124)

            VStack(alignment: .leading, spacing: 7) {
                providerHeader(provider, compact: false)
                HStack(alignment: .top, spacing: 12) {
                    resetSummary(outer, compact: true)
                    if let inner = provider.rings.dropFirst().first {
                        resetSummary(inner, compact: true)
                    }
                }
                additionalRows(provider.additionalWindows, limit: 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }

    private func largeLayout(
        provider: WidgetProviderPresentation,
        outer: WidgetRingPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            providerHeader(provider, compact: false)
            HStack(alignment: .center, spacing: 16) {
                DualUsageRing(
                    outer: outer,
                    inner: provider.rings.dropFirst().first,
                    outerAccent: palette.dataAccent(.outerRing),
                    innerAccent: palette.dataAccent(.innerRing),
                    percentageMode: presentation.configuration.percentageMode,
                    track: palette.track
                )
                .frame(width: 128, height: 128)

                VStack(alignment: .leading, spacing: 8) {
                    resetSummary(outer, compact: false)
                    if let inner = provider.rings.dropFirst().first {
                        resetSummary(inner, compact: false)
                    }
                    additionalRows(provider.additionalWindows, limit: 2)
                }
            }
            historyView
                .frame(maxHeight: .infinity)
            metadata(provider)
        }
        .padding(14)
    }

    private func extraLargeLayout(
        provider: WidgetProviderPresentation,
        outer: WidgetRingPresentation
    ) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                providerHeader(provider, compact: false)
                HStack(spacing: 16) {
                    DualUsageRing(
                        outer: outer,
                        inner: provider.rings.dropFirst().first,
                        outerAccent: palette.dataAccent(.outerRing),
                        innerAccent: palette.dataAccent(.innerRing),
                        percentageMode: presentation.configuration.percentageMode,
                        track: palette.track
                    )
                    .frame(width: 150, height: 150)
                    VStack(alignment: .leading, spacing: 10) {
                        resetSummary(outer, compact: false)
                        if let inner = provider.rings.dropFirst().first {
                            resetSummary(inner, compact: false)
                        }
                    }
                }
                additionalRows(provider.additionalWindows, limit: 4)
                metadata(provider)
            }
            .frame(maxWidth: 290, alignment: .leading)

            Divider()
            historyView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
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
        }
        .accessibilityElement(children: .combine)
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
    private var historyView: some View {
        if presentation.modules.contains(.history), let history = presentation.history {
            if let message = history.availabilityMessage {
                WidgetStateView(title: message, systemImage: "calendar.badge.exclamationmark")
            } else {
                switch presentation.configuration.historyStyle {
                case .heatMap, .bars:
                    UsageHeatMap(
                        projection: history,
                        lowAccent: palette.dataAccent(.heatLow),
                        moderateAccent: palette.dataAccent(.heatModerate),
                        highAccent: palette.dataAccent(.heatHigh),
                        veryHighAccent: palette.dataAccent(.heatVeryHigh)
                    )
                case .trend:
                    UsageTrendChart(
                        projection: history,
                        lineAccent: palette.dataAccent(.trendLine),
                        pointAccent: palette.dataAccent(.trendPoint)
                    )
                case .none:
                    EmptyView()
                }
            }
        }
    }

    private func metadata(_ provider: WidgetProviderPresentation) -> some View {
        HStack(spacing: 10) {
            if presentation.modules.contains(.status) {
                Label(provider.status, systemImage: "circle.fill")
                    .lineLimit(1)
            }
            if presentation.modules.contains(.freshness) {
                Label(
                    presentation.freshness == .fresh ? "Current" : "Stale",
                    systemImage: presentation.freshness == .fresh ? "checkmark.circle" : "exclamationmark.triangle"
                )
            }
        }
        .font(.caption2)
        .foregroundStyle(palette.secondaryText)
        .accessibilityElement(children: .combine)
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
