import AgentMeterWidgetCore
import Foundation
import SwiftUI

enum DashboardWidgetDestination {
    static func url(for presentation: WidgetPresentation) -> URL {
        switch presentation.configuration.tapDestination {
        case .overview:
            return AgentMeterRoute.overview.url
        case .agents:
            return AgentMeterRoute.agents.url
        case .providerDetail:
            guard let providerID = presentation.providers.first(where: {
                $0.availability == .available
            })?.id,
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
        widgetURL = DashboardWidgetDestination.url(for: presentation)
        if presentation.family == .small {
            providerURLs = [:]
            return
        }

        providerURLs = presentation.providers.reduce(into: [:]) { result, provider in
            guard provider.availability == .available,
                  AgentMeterRoute.isValidProviderID(provider.id) else { return }
            result[provider.id] = AgentMeterRoute.provider(provider.id).url
        }
    }

    func providerURL(for provider: WidgetProviderPresentation) -> URL? {
        guard provider.availability == .available else { return nil }
        return providerURLs[provider.id]
    }
}

struct DashboardWidgetView: View {
    let presentation: WidgetPresentation
    var nowEpoch: Int = Int(Date().timeIntervalSince1970)

    @Environment(\.colorScheme) private var colorScheme

    private var palette: WidgetThemePalette {
        WidgetThemePalette(
            theme: presentation.configuration.theme,
            providerID: presentation.providers.first?.id ?? "",
            colorScheme: colorScheme
        )
    }

    /// Density-compact trims paddings and gaps by ~2pt.
    private var d: CGFloat {
        presentation.configuration.density == .compact ? 2 : 0
    }

    var interactionComposition: DashboardWidgetInteractions {
        DashboardWidgetInteractions(presentation: presentation)
    }

    var body: some View {
        Group {
            if let widgetURL = interactionComposition.widgetURL {
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
                WidgetStateView(
                    title: "Providers unavailable",
                    systemImage: "person.2.badge.gearshape"
                )
                .padding()
            } else {
                familyLayout
            }
        }
        .foregroundStyle(palette.primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            ZStack {
                Rectangle().fill(palette.cardFill)
                ContainerRelativeShape()
                    .strokeBorder(palette.border, lineWidth: 1)
            }
        }
        .preferredColorScheme(palette.preferredColorScheme)
    }

    @ViewBuilder
    private var familyLayout: some View {
        switch presentation.family {
        case .small:
            smallLayout
        case .medium:
            mediumLayout
        case .large:
            largeLayout
        case .extraLarge:
            extraLargeLayout
        }
    }

    // MARK: - Small

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8 - min(d, 2)) {
            HStack(spacing: 6) {
                Text("AGENTS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(palette.tertiaryText)
                Spacer(minLength: 4)
                overflowChip
            }

            ForEach(Array(presentation.providers.prefix(2)), id: \.id) { provider in
                smallRow(provider)
            }

            Spacer(minLength: 0)
        }
        .padding(12 - d)
    }

    private func smallRow(_ provider: WidgetProviderPresentation) -> some View {
        let hero = provider.rings.first
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                WidgetProviderMark(
                    providerID: provider.id,
                    name: provider.name,
                    accent: accent(for: provider.id),
                    size: 13
                )
                Text(provider.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(hero?.displayedPercent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(
                        hero?.displayedPercent == nil
                            ? palette.secondaryText
                            : palette.primaryText
                    )
            }

            UsageTrackCapsule(
                displayedPercent: hero?.displayedPercent,
                accent: accent(for: provider.id),
                palette: palette,
                height: 3
            )

            Text(hero.map(compactReset) ?? "Agent unavailable")
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(palette.tertiaryText)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Medium

    private var mediumLayout: some View {
        HStack(spacing: 0) {
            let providers = Array(presentation.providers.prefix(4))
            ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                linked(provider) {
                    mediumColumn(provider)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if index < providers.count - 1 {
                    Rectangle()
                        .fill(palette.rule)
                        .frame(width: 1)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(.vertical, 16 - d)
        .padding(.horizontal, 8 - min(d, 2))
    }

    private func mediumColumn(_ provider: WidgetProviderPresentation) -> some View {
        let hero = provider.rings.first
        let providerAccent = accent(for: provider.id)
        return VStack(spacing: 0) {
            HStack(spacing: 4) {
                WidgetProviderMark(
                    providerID: provider.id,
                    name: provider.name,
                    accent: providerAccent,
                    size: 11
                )
                Text(provider.name)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            if let hero {
                SingleUsageRing(
                    displayedPercent: hero.displayedPercent,
                    accent: providerAccent,
                    track: palette.track
                ) {
                    Text(hero.displayedPercent.map { "\($0)%" } ?? "—")
                        .font(.system(size: 12.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(
                            hero.displayedPercent == nil
                                ? palette.secondaryText
                                : palette.primaryText
                        )
                }
                .frame(width: 56, height: 56)
            } else {
                Text("—")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 56, height: 56)
            }

            Spacer(minLength: 4)

            VStack(spacing: 1) {
                if let hero {
                    Text(hero.label.uppercased())
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(palette.tertiaryText)
                        .lineLimit(1)
                    Text(compactReset(hero))
                        .font(.system(size: 9.5))
                        .monospacedDigit()
                        .foregroundStyle(palette.tertiaryText)
                        .lineLimit(1)
                } else {
                    Text("Agent unavailable")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.tertiaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Large

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 9 - min(d, 2)) {
            header

            if trendSeries.isEmpty == false {
                trendModule(chartHeight: 46, showsYAxis: false, lineWidth: 1.6)
                rule
            }

            VStack(alignment: .leading, spacing: 8 - min(d, 2)) {
                ForEach(presentation.providers, id: \.id) { provider in
                    linked(provider) {
                        DashboardProviderRow(
                            provider: provider,
                            theme: presentation.configuration.theme,
                            nowEpoch: nowEpoch
                        )
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)

            if presentation.modules.contains(.history) {
                rule
                DashboardHistoryPanel(
                    history: presentation.history,
                    periodLabel: presentation.configuration.historyPeriod.displayLabel,
                    accent: accent(for: presentation.providers.first?.id ?? ""),
                    palette: palette,
                    cellHeight: 8
                )
            }
        }
        .padding(16 - d)
    }

    // MARK: - Extra large

    private var extraLargeLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10 - min(d, 2)) {
                header

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2),
                    spacing: 10
                ) {
                    ForEach(Array(presentation.providers.prefix(4)), id: \.id) { provider in
                        linked(provider) {
                            miniCard(provider)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(palette.rule)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 8 - min(d, 2)) {
                if trendSeries.isEmpty == false {
                    trendModule(chartHeight: 132, showsYAxis: true, lineWidth: 1.8)
                    rule
                }

                if presentation.modules.contains(.history) {
                    DashboardHistoryPanel(
                        history: presentation.history,
                        periodLabel: presentation.configuration.historyPeriod.displayLabel,
                        accent: accent(for: presentation.providers.first?.id ?? ""),
                        palette: palette,
                        cellHeight: 17,
                        cornerRadius: 5,
                        columns: 10
                    )
                }

                Spacer(minLength: 0)
            }
            .frame(width: 330)
        }
        .padding(18 - d)
    }

    private func miniCard(_ provider: WidgetProviderPresentation) -> some View {
        let hero = provider.rings.first
        let providerAccent = accent(for: provider.id)
        let remaining = Array(provider.rings.dropFirst()) + provider.additionalWindows
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                WidgetProviderMark(
                    providerID: provider.id,
                    name: provider.name,
                    accent: providerAccent,
                    size: 13
                )
                Text(provider.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                StatusDot(
                    health: provider.healthState,
                    worstUsedPercent: worstUsedPercent(provider),
                    size: 6,
                    glows: false
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(hero?.displayedPercent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 19, weight: .bold))
                    .tracking(-0.4)
                    .monospacedDigit()
                    .foregroundStyle(
                        hero?.displayedPercent == nil
                            ? palette.secondaryText
                            : palette.primaryText
                    )
                Text(
                    hero.map { "\($0.label.uppercased()) · \(compactReset($0))" }
                        ?? "Agent unavailable"
                )
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(palette.tertiaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            }

            Spacer(minLength: 2)

            ForEach(Array(remaining.prefix(2)), id: \.windowKind) { window in
                UsageBarRow(
                    label: window.label,
                    displayedPercent: window.displayedPercent,
                    accent: providerAccent,
                    palette: palette,
                    labelSize: 9,
                    valueSize: 9,
                    trackHeight: 3
                )
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.chipFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.chipBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Shared modules

    private var header: some View {
        HStack(spacing: 7) {
            Text("AgentMeter")
                .font(.system(size: 13, weight: .bold))
            Spacer(minLength: 4)
            overflowChip
            if presentation.modules.contains(.freshness) {
                LivePill(freshness: presentation.freshness)
            }
        }
    }

    @ViewBuilder
    private var overflowChip: some View {
        if presentation.overflowCount > 0 {
            Text("+\(presentation.overflowCount)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(palette.chipFill, in: Capsule())
                .accessibilityLabel("\(presentation.overflowCount) more providers")
        }
    }

    private func trendModule(
        chartHeight: CGFloat,
        showsYAxis: Bool,
        lineWidth: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("LAST 24 HOURS")
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(palette.tertiaryText)
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    ForEach(trendSeries) { series in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(series.accent)
                                .frame(width: 5, height: 5)
                            Text(series.name)
                                .font(.system(size: 8))
                                .foregroundStyle(palette.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                }
            }

            HourlyTrendChart(
                series: trendSeries,
                palette: palette,
                height: chartHeight,
                showsYAxis: showsYAxis,
                lineWidth: lineWidth
            )
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(palette.rule)
            .frame(height: 1)
    }

    // MARK: - Helpers

    private var trendSeries: [HourlyTrendSeries] {
        presentation.providers.compactMap { provider in
            guard provider.hourlyTrend.count >= 2 else { return nil }
            return HourlyTrendSeries(
                id: provider.id,
                name: provider.name,
                accent: accent(for: provider.id),
                points: provider.hourlyTrend
            )
        }
    }

    @ViewBuilder
    private func linked(
        _ provider: WidgetProviderPresentation,
        @ViewBuilder content: () -> some View
    ) -> some View {
        if let destination = interactionComposition.providerURL(for: provider) {
            Link(destination: destination) {
                content()
            }
            .buttonStyle(.plain)
        } else {
            content()
        }
    }

    private func accent(for providerID: String) -> Color {
        WidgetThemePalette(
            theme: presentation.configuration.theme,
            providerID: providerID,
            colorScheme: colorScheme
        )
        .dataAccent(.providerMark)
    }

    private func worstUsedPercent(_ provider: WidgetProviderPresentation) -> Int? {
        (provider.rings + provider.additionalWindows)
            .compactMap(\.usedPercent)
            .max()
    }

    private func compactReset(_ ring: WidgetRingPresentation) -> String {
        WidgetResetPhrasing.compactText(
            WidgetResetPhrasing.phrase(for: ring.resetState, nowEpoch: nowEpoch),
            nowEpoch: nowEpoch
        )
    }
}
