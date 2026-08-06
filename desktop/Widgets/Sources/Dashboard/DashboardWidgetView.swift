import AgentMeterCore
import AgentMeterWidgetCore
import SwiftUI

enum DashboardHistoryEmphasis: Hashable {
    case hidden
    case compact
    case balanced
    case expanded
}

enum DashboardHistoryPlacement: Hashable {
    case hidden
    case below
    case beside
}

struct DashboardLayoutPlan: Hashable {
    let rowStyle: DashboardProviderRowStyle
    let providerColumns: Int
    let spacing: CGFloat
    let padding: CGFloat
    let historyEmphasis: DashboardHistoryEmphasis
    let historyPlacement: DashboardHistoryPlacement
    let providerMaximumWidth: CGFloat?
    let showsMetadata: Bool

    init(presentation: WidgetPresentation) {
        let hasHistory = DashboardWidgetSemantics(presentation: presentation).showsHistory
        let comfortableSpacing: CGFloat = presentation.configuration.density == .compact ? 4 : 7

        switch presentation.family {
        case .small:
            rowStyle = .outerOnly
            providerColumns = 1
            spacing = presentation.configuration.layout == .compact ? 2 : 6
            padding = presentation.configuration.layout == .compact ? 7 : 9
            historyEmphasis = .hidden
            historyPlacement = .hidden
            providerMaximumWidth = nil
            showsMetadata = false
        case .medium:
            rowStyle = presentation.configuration.layout == .compact ? .outerOnly : .dualCompact
            providerColumns = 2
            spacing = presentation.configuration.layout == .compact ? 2 : comfortableSpacing
            padding = presentation.configuration.layout == .compact ? 7 : 9
            historyEmphasis = .hidden
            historyPlacement = .hidden
            providerMaximumWidth = nil
            showsMetadata = false
        case .large:
            switch presentation.configuration.layout {
            case .automatic:
                rowStyle = .detailed
                providerColumns = 2
                spacing = comfortableSpacing
                padding = 12
                historyEmphasis = hasHistory ? .balanced : .hidden
                historyPlacement = hasHistory ? .below : .hidden
                providerMaximumWidth = nil
                showsMetadata = true
            case .usageAndRings:
                rowStyle = .dualCompact
                providerColumns = 2
                spacing = comfortableSpacing
                padding = 10
                historyEmphasis = hasHistory ? .compact : .hidden
                historyPlacement = hasHistory ? .below : .hidden
                providerMaximumWidth = nil
                showsMetadata = true
            case .compact:
                rowStyle = .outerOnly
                providerColumns = 2
                spacing = 2
                padding = 9
                historyEmphasis = hasHistory ? .balanced : .hidden
                historyPlacement = hasHistory ? .below : .hidden
                providerMaximumWidth = nil
                showsMetadata = false
            case .expanded:
                rowStyle = .analyticsCompact
                providerColumns = 1
                spacing = 4
                padding = 12
                historyEmphasis = hasHistory ? .expanded : .hidden
                historyPlacement = hasHistory ? .beside : .hidden
                providerMaximumWidth = 132
                showsMetadata = true
            }
        case .extraLarge:
            switch presentation.configuration.layout {
            case .automatic:
                rowStyle = .expanded
                providerColumns = 2
                spacing = comfortableSpacing
                padding = 14
                historyEmphasis = hasHistory ? .balanced : .hidden
                historyPlacement = hasHistory ? .beside : .hidden
                providerMaximumWidth = 380
                showsMetadata = true
            case .usageAndRings:
                rowStyle = .expanded
                providerColumns = 2
                spacing = comfortableSpacing
                padding = 12
                historyEmphasis = hasHistory ? .compact : .hidden
                historyPlacement = hasHistory ? .beside : .hidden
                providerMaximumWidth = 430
                showsMetadata = true
            case .compact:
                rowStyle = .outerOnly
                providerColumns = 2
                spacing = 2
                padding = 10
                historyEmphasis = hasHistory ? .balanced : .hidden
                historyPlacement = hasHistory ? .beside : .hidden
                providerMaximumWidth = 300
                showsMetadata = false
            case .expanded:
                rowStyle = .analyticsCompact
                providerColumns = 2
                spacing = 4
                padding = 14
                historyEmphasis = hasHistory ? .expanded : .hidden
                historyPlacement = hasHistory ? .beside : .hidden
                providerMaximumWidth = 280
                showsMetadata = true
            }
        }
    }
}

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

struct DashboardWidgetInteractions: Equatable {
    let widgetURL: URL?
    let providerURLs: [String: URL]

    init(presentation: WidgetPresentation) {
        if presentation.family == .small {
            widgetURL = DashboardWidgetDestination.url(for: presentation)
            providerURLs = [:]
            return
        }

        widgetURL = nil
        providerURLs = presentation.providers.reduce(into: [:]) { result, provider in
            guard AgentMeterRoute.isValidProviderID(provider.id) else { return }
            result[provider.id] = AgentMeterRoute.provider(provider.id).url
        }
    }
}

struct DashboardWidgetView: View {
    let presentation: WidgetPresentation
    @Environment(\.colorScheme) private var colorScheme

    private var semantics: DashboardWidgetSemantics {
        DashboardWidgetSemantics(presentation: presentation)
    }

    private var layoutPlan: DashboardLayoutPlan {
        DashboardLayoutPlan(presentation: presentation)
    }

    private var palette: WidgetThemePalette {
        WidgetThemePalette(
            theme: presentation.configuration.theme,
            providerID: presentation.providers.first?.id ?? "",
            colorScheme: colorScheme
        )
    }

    private var interactions: DashboardWidgetInteractions {
        DashboardWidgetInteractions(presentation: presentation)
    }

    var body: some View {
        Group {
            if let widgetURL = interactions.widgetURL {
                widgetContent.widgetURL(widgetURL)
            } else {
                widgetContent
            }
        }
        .privacySensitive()
    }

    private var widgetContent: some View {
        Group {
            if presentation.providers.isEmpty {
                WidgetStateView(title: "Providers unavailable", systemImage: "person.2.badge.gearshape")
                    .padding()
            } else {
                familyLayout
            }
        }
        .foregroundStyle(palette.primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { palette.background }
        .preferredColorScheme(palette.preferredColorScheme)
    }

    @ViewBuilder
    private var familyLayout: some View {
        switch layoutPlan.historyPlacement {
        case .hidden:
            VStack(alignment: .leading, spacing: 6) {
                header(compact: presentation.family == .small || presentation.family == .medium)
                providerRows
            }
            .padding(layoutPlan.padding)
        case .below:
            VStack(alignment: .leading, spacing: 7) {
                header(compact: false)
                providerRows
                historyPanel
                    .frame(
                        height: layoutPlan.historyEmphasis == .compact ? 86 : nil
                    )
                    .frame(maxHeight: layoutPlan.historyEmphasis == .compact ? nil : .infinity)
            }
            .padding(layoutPlan.padding)
        case .beside:
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    header(compact: false)
                    providerRows
                }
                .frame(maxWidth: layoutPlan.providerMaximumWidth, alignment: .leading)

                if semantics.showsHistory {
                    Divider()
                    historyPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(layoutPlan.padding)
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
    private var providerRows: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: layoutPlan.spacing),
                count: layoutPlan.providerColumns
            ),
            alignment: .leading,
            spacing: layoutPlan.spacing
        ) {
            ForEach(presentation.providers, id: \.id) { provider in
                if let destination = interactions.providerURLs[provider.id] {
                    Link(destination: destination) {
                        providerRow(provider)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        palette.track.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                } else {
                    providerRow(provider)
                }
            }
        }
    }

    private func providerRow(_ provider: WidgetProviderPresentation) -> some View {
        DashboardProviderRow(
            provider: provider,
            percentageMode: presentation.configuration.percentageMode,
            modules: presentation.modules,
            freshness: presentation.freshness,
            showsResetCountdown: presentation.configuration.showsResetCountdown,
            showsAbsoluteResetDate: presentation.configuration.showsAbsoluteResetDate,
            theme: presentation.configuration.theme,
            style: layoutPlan.rowStyle,
            additionalWindowLimit: semantics.additionalWindowLimit,
            showsMetadata: layoutPlan.showsMetadata
        )
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
