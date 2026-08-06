import AgentMeterCore
import AgentMeterWidgetCore
import SwiftUI

struct DashboardWidgetSemantics: Equatable {
    let visibleProviderCount: Int
    let overflowLabel: String?
    let showsHistory: Bool
    let additionalWindowLimit: Int

    init(presentation: WidgetPresentation) {
        visibleProviderCount = presentation.providers.count
        overflowLabel = presentation.overflowCount > 0 ? "+\(presentation.overflowCount)" : nil
        showsHistory = (presentation.family == .large || presentation.family == .extraLarge)
            && presentation.modules.contains(.history)
            && presentation.history != nil
        additionalWindowLimit = presentation.family == .extraLarge ? 2 : 0
    }
}

enum DashboardWidgetDestination {
    static func url(for presentation: WidgetPresentation) -> URL {
        switch presentation.configuration.tapDestination {
        case .overview:
            return AgentMeterRoute.overview.url
        case .agents:
            return AgentMeterRoute.agents.url
        case .providerDetail:
            guard let providerID = presentation.providers.first?.id,
                  AgentMeterRoute.isValidProviderID(providerID) else {
                return AgentMeterRoute.overview.url
            }
            return AgentMeterRoute.provider(providerID).url
        }
    }
}

struct DashboardWidgetView: View {
    let presentation: WidgetPresentation
    @Environment(\.colorScheme) private var colorScheme

    private var semantics: DashboardWidgetSemantics {
        DashboardWidgetSemantics(presentation: presentation)
    }

    private var palette: WidgetThemePalette {
        WidgetThemePalette(
            theme: presentation.configuration.theme,
            providerID: presentation.providers.first?.id ?? "",
            colorScheme: colorScheme
        )
    }

    var body: some View {
        Group {
            if presentation.providers.isEmpty {
                WidgetStateView(title: "Providers unavailable", systemImage: "person.2.badge.gearshape")
                    .padding()
            } else {
                familyLayout
            }
        }
        .foregroundStyle(palette.primaryText)
        .containerBackground(for: .widget) { palette.background }
        .preferredColorScheme(palette.preferredColorScheme)
        .widgetURL(DashboardWidgetDestination.url(for: presentation))
        .privacySensitive()
    }

    @ViewBuilder
    private var familyLayout: some View {
        switch presentation.family {
        case .small:
            VStack(alignment: .leading, spacing: 6) {
                header(compact: true)
                providerRows(style: .outerOnly, columns: 1)
            }
            .padding(9)
        case .medium:
            VStack(alignment: .leading, spacing: 5) {
                header(compact: true)
                providerRows(style: .dualCompact, columns: 2)
            }
            .padding(9)
        case .large:
            VStack(alignment: .leading, spacing: 7) {
                header(compact: false)
                providerRows(style: .detailed, columns: 2)
                historyPanel
                    .frame(maxHeight: .infinity)
            }
            .padding(12)
        case .extraLarge:
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    header(compact: false)
                    providerRows(style: .expanded, columns: 2)
                }
                .frame(maxWidth: 380, alignment: .leading)

                if semantics.showsHistory {
                    Divider()
                    historyPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(14)
        }
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .foregroundStyle(palette.dataAccent(.outerRing))
                .accessibilityHidden(true)
            Text("AgentMeter")
                .font(compact ? .caption.weight(.bold) : .headline)
            Spacer(minLength: 2)
            if presentation.modules.contains(.freshness), presentation.family == .large || presentation.family == .extraLarge {
                Text(presentation.freshness == .fresh ? "Current" : "Stale")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }
            if let overflow = semantics.overflowLabel {
                Text(overflow)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(palette.track, in: Capsule())
                    .accessibilityLabel("\(presentation.overflowCount) more providers")
            }
        }
    }

    @ViewBuilder
    private func providerRows(
        style: DashboardProviderRowStyle,
        columns: Int
    ) -> some View {
        let spacing: CGFloat = presentation.configuration.density == .compact ? 4 : 7
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
            alignment: .leading,
            spacing: spacing
        ) {
            ForEach(presentation.providers, id: \.id) { provider in
                DashboardProviderRow(
                    provider: provider,
                    percentageMode: presentation.configuration.percentageMode,
                    modules: presentation.modules,
                    freshness: presentation.freshness,
                    showsResetCountdown: presentation.configuration.showsResetCountdown,
                    showsAbsoluteResetDate: presentation.configuration.showsAbsoluteResetDate,
                    theme: presentation.configuration.theme,
                    style: style,
                    additionalWindowLimit: semantics.additionalWindowLimit
                )
            }
        }
    }

    @ViewBuilder
    private var historyPanel: some View {
        if semantics.showsHistory, let history = presentation.history {
            DashboardHistoryPanel(
                projection: history,
                semantics: DashboardHistorySemantics(presentation: presentation),
                lowAccent: palette.dataAccent(.heatLow),
                moderateAccent: palette.dataAccent(.heatModerate),
                highAccent: palette.dataAccent(.heatHigh),
                veryHighAccent: palette.dataAccent(.heatVeryHigh),
                lineAccent: palette.dataAccent(.trendLine),
                pointAccent: palette.dataAccent(.trendPoint)
            )
        }
    }
}
