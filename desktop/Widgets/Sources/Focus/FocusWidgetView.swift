import AgentMeterWidgetCore
import Foundation
import SwiftUI

struct FocusWidgetView: View {
    let presentation: WidgetPresentation
    var nowEpoch: Int = Int(Date().timeIntervalSince1970)

    @Environment(\.colorScheme) private var colorScheme

    private var provider: WidgetProviderPresentation? { presentation.providers.first }

    private var palette: WidgetThemePalette {
        WidgetThemePalette(
            theme: presentation.configuration.theme,
            providerID: provider?.id ?? "",
            colorScheme: colorScheme
        )
    }

    private var accent: Color { palette.dataAccent(.providerMark) }

    /// Density-compact trims paddings and gaps by ~2pt.
    private var d: CGFloat {
        presentation.configuration.density == .compact ? 2 : 0
    }

    var body: some View {
        Group {
            if let provider {
                if let hero = provider.rings.first {
                    layout(provider: provider, hero: hero)
                } else {
                    unavailableUsage(provider: provider)
                }
            } else {
                WidgetStateView(
                    title: "Provider unavailable",
                    systemImage: "person.crop.circle.badge.questionmark"
                )
                .padding()
            }
        }
        .foregroundStyle(palette.primaryText)
        .containerBackground(for: .widget) {
            ZStack {
                Rectangle().fill(palette.cardFill)
                ContainerRelativeShape()
                    .strokeBorder(palette.border, lineWidth: 1)
            }
        }
        .preferredColorScheme(palette.preferredColorScheme)
        .widgetURL(destinationURL)
        .privacySensitive()
    }

    // MARK: - Family layouts

    @ViewBuilder
    private func layout(
        provider: WidgetProviderPresentation,
        hero: WidgetRingPresentation
    ) -> some View {
        switch presentation.family {
        case .small:
            smallLayout(provider: provider, hero: hero)
        case .medium:
            mediumLayout(provider: provider, hero: hero)
        case .large, .extraLarge:
            largeLayout(provider: provider, hero: hero)
        }
    }

    private func smallLayout(
        provider: WidgetProviderPresentation,
        hero: WidgetRingPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                WidgetProviderMark(
                    providerID: provider.id,
                    name: provider.name,
                    accent: accent,
                    size: 15
                )
                Text(provider.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                StatusDot(
                    health: provider.healthState,
                    worstUsedPercent: worstUsedPercent(provider)
                )
            }
            .accessibilityElement(children: .combine)

            Text(hero.label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(palette.tertiaryText)
                .lineLimit(1)
                .padding(.top, 9 - d)

            heroNumber(hero)
                .padding(.top, 1)

            resetLine(hero, fontSize: 9.5)
                .padding(.top, 2)

            Spacer(minLength: 6)

            VStack(alignment: .leading, spacing: 6 - min(d, 2)) {
                ForEach(
                    Array(remainingWindows(provider).prefix(2)),
                    id: \.windowKind
                ) { window in
                    UsageBarRow(
                        label: window.label,
                        displayedPercent: window.displayedPercent,
                        accent: accent,
                        palette: palette,
                        labelSize: 10,
                        valueSize: 10.5,
                        trackHeight: 3.5
                    )
                }
            }
        }
        .padding(13 - d)
    }

    private func mediumLayout(
        provider: WidgetProviderPresentation,
        hero: WidgetRingPresentation
    ) -> some View {
        HStack(spacing: 18 - d) {
            SingleUsageRing(
                displayedPercent: hero.displayedPercent,
                accent: accent,
                track: palette.track,
                lineWidth: 6,
                glows: true
            ) {
                ringCenter(hero, valueSize: 22, tracking: -0.4)
            }
            .frame(width: 94, height: 94)

            VStack(alignment: .leading, spacing: 11 - d) {
                HStack(spacing: 7) {
                    WidgetProviderMark(
                        providerID: provider.id,
                        name: provider.name,
                        accent: accent,
                        size: 16
                    )
                    Text(provider.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(compactReset(hero))
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(palette.tertiaryText)
                        .lineLimit(1)
                    StatusDot(
                        health: provider.healthState,
                        worstUsedPercent: worstUsedPercent(provider)
                    )
                }
                .accessibilityElement(children: .combine)

                ForEach(
                    Array(remainingWindows(provider).prefix(2)),
                    id: \.windowKind
                ) { window in
                    UsageBarRow(
                        label: window.label,
                        displayedPercent: window.displayedPercent,
                        accent: accent,
                        palette: palette,
                        labelSize: 11,
                        valueSize: 11,
                        trackHeight: 4,
                        resetText: longReset(window)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18 - d)
    }

    private func largeLayout(
        provider: WidgetProviderPresentation,
        hero: WidgetRingPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 11 - d) {
            HStack(spacing: 7) {
                WidgetProviderMark(
                    providerID: provider.id,
                    name: provider.name,
                    accent: accent,
                    size: 18
                )
                Text(provider.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if presentation.modules.contains(.status) {
                    WidgetHealthBadges(
                        labels: WidgetHealthSemantics.mandatoryLabels(
                            provider: provider,
                            freshness: presentation.freshness
                        ),
                        compact: true
                    )
                }
                if presentation.modules.contains(.freshness) {
                    LivePill(freshness: presentation.freshness)
                }
                StatusDot(
                    health: provider.healthState,
                    worstUsedPercent: worstUsedPercent(provider)
                )
            }
            .accessibilityElement(children: .combine)

            HStack {
                Spacer(minLength: 0)
                SingleUsageRing(
                    displayedPercent: hero.displayedPercent,
                    accent: accent,
                    track: palette.track,
                    lineWidth: 7,
                    glows: true
                ) {
                    ringCenter(hero, valueSize: 24, tracking: -0.4)
                }
                .frame(width: 110, height: 110)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)

            resetLine(hero, fontSize: 10)

            VStack(alignment: .leading, spacing: 8 - min(d, 2)) {
                ForEach(remainingWindows(provider), id: \.windowKind) { window in
                    UsageBarRow(
                        label: window.label,
                        displayedPercent: window.displayedPercent,
                        accent: accent,
                        palette: palette,
                        labelSize: 12,
                        valueSize: 12,
                        trackHeight: 4,
                        resetText: longReset(window)
                    )
                }
            }

            Spacer(minLength: 0)

            if let history = presentation.history {
                Rectangle()
                    .fill(palette.rule)
                    .frame(height: 1)
                historyModule(history)
            }
        }
        .padding(16 - d)
    }

    // MARK: - Modules

    @ViewBuilder
    private func historyModule(_ history: WidgetHistoryProjection) -> some View {
        if let message = history.availabilityMessage {
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(palette.tertiaryText)
                .lineLimit(2)
        } else if history.trendPoints.isEmpty == false {
            VStack(alignment: .leading, spacing: 5) {
                historyCaption(
                    title: (history.windowLabel ?? "Usage").uppercased(),
                    detail: presentation.configuration.historyPeriod.displayLabel
                )
                UsageTrendChart(
                    trendPoints: history.trendPoints,
                    accent: accent,
                    palette: palette
                )
            }
        } else if history.cells.isEmpty == false {
            VStack(alignment: .leading, spacing: 5) {
                historyCaption(
                    title: "ALLOWANCE CONSUMED",
                    detail: presentation.configuration.historyPeriod.displayLabel
                )
                ConsumptionStrip(
                    cells: history.cells,
                    accent: accent,
                    palette: palette,
                    cellHeight: 8
                )
            }
        }
    }

    private func historyCaption(title: String, detail: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(palette.tertiaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(detail)
                .font(.system(size: 8.5))
                .foregroundStyle(palette.tertiaryText)
                .lineLimit(1)
        }
    }

    // MARK: - Pieces

    private func ringCenter(
        _ hero: WidgetRingPresentation,
        valueSize: CGFloat,
        tracking: CGFloat
    ) -> some View {
        VStack(spacing: 1) {
            if let percent = hero.displayedPercent {
                Text("\(percent)%")
                    .font(.system(size: valueSize, weight: .bold))
                    .tracking(tracking)
                    .monospacedDigit()
                    .foregroundStyle(palette.primaryText)
            } else {
                Text("—")
                    .font(.system(size: valueSize, weight: .bold))
                    .foregroundStyle(palette.secondaryText)
            }
            Text(hero.label.uppercased())
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(palette.tertiaryText)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func heroNumber(_ hero: WidgetRingPresentation) -> some View {
        if let percent = hero.displayedPercent {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(percent)")
                    .font(.system(size: 27, weight: .bold))
                    .tracking(-0.5)
                    .monospacedDigit()
                    .foregroundStyle(palette.primaryText)
                Text("%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("—")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(palette.secondaryText)
                Text("Not reported")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    private func resetLine(
        _ ring: WidgetRingPresentation,
        fontSize: CGFloat
    ) -> some View {
        ResetSummary(
            presentation: ring,
            showsCountdown: presentation.configuration.showsResetCountdown,
            showsAbsoluteDate: presentation.configuration.showsAbsoluteResetDate,
            showsLabel: false,
            nowEpoch: nowEpoch
        )
        .font(.system(size: fontSize))
        .foregroundStyle(palette.tertiaryText)
    }

    private func unavailableUsage(provider: WidgetProviderPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                WidgetProviderMark(
                    providerID: provider.id,
                    name: provider.name,
                    accent: accent,
                    size: 15
                )
                Text(provider.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                StatusDot(health: provider.healthState, worstUsedPercent: nil)
            }
            WidgetStateView(
                title: "Allowance unavailable",
                systemImage: "gauge.with.dots.needle.0percent"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(13 - d)
    }

    // MARK: - Data helpers

    private func remainingWindows(
        _ provider: WidgetProviderPresentation
    ) -> [WidgetRingPresentation] {
        Array(provider.rings.dropFirst()) + provider.additionalWindows
    }

    private func worstUsedPercent(_ provider: WidgetProviderPresentation) -> Int? {
        (provider.rings + provider.additionalWindows)
            .compactMap(\.usedPercent)
            .max()
    }

    private func longReset(_ ring: WidgetRingPresentation) -> String {
        WidgetResetPhrasing.longText(
            WidgetResetPhrasing.phrase(for: ring.resetState, nowEpoch: nowEpoch),
            nowEpoch: nowEpoch
        )
    }

    private func compactReset(_ ring: WidgetRingPresentation) -> String {
        WidgetResetPhrasing.compactText(
            WidgetResetPhrasing.phrase(for: ring.resetState, nowEpoch: nowEpoch),
            nowEpoch: nowEpoch
        )
    }

    private var destinationURL: URL {
        switch presentation.configuration.tapDestination {
        case .overview:
            return AgentMeterRoute.overview.url
        case .agents:
            return AgentMeterRoute.agents.url
        case .providerDetail:
            guard let providerID = provider?.id,
                  AgentMeterRoute.isValidProviderID(providerID) else {
                return AgentMeterRoute.overview.url
            }
            return AgentMeterRoute.provider(providerID).url
        }
    }
}
