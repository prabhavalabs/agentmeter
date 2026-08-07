import AgentMeterWidgetCore
import SwiftUI

/// Large-dashboard provider row from the v2 design language: an accent icon
/// chip, name, usage track, hero percent, and a secondary-window sub-line.
struct DashboardProviderRow: View {
    let provider: WidgetProviderPresentation
    let theme: WidgetTheme
    let nowEpoch: Int

    @Environment(\.colorScheme) private var colorScheme

    private var palette: WidgetThemePalette {
        WidgetThemePalette(theme: theme, providerID: provider.id, colorScheme: colorScheme)
    }

    private var accent: Color { palette.dataAccent(.providerMark) }

    private var hero: WidgetRingPresentation? { provider.rings.first }

    private var secondaryWindows: [WidgetRingPresentation] {
        Array(provider.rings.dropFirst()) + provider.additionalWindows
    }

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(0.1))
                .frame(width: 26, height: 26)
                .overlay(
                    WidgetProviderMark(
                        providerID: provider.id,
                        name: provider.name,
                        accent: accent,
                        size: 14
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(provider.name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 48, alignment: .leading)
                    UsageTrackCapsule(
                        displayedPercent: hero?.displayedPercent,
                        accent: accent,
                        palette: palette,
                        height: 4
                    )
                    Text(hero?.displayedPercent.map { "\($0)%" } ?? "—")
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(
                            hero?.displayedPercent == nil
                                ? palette.secondaryText
                                : palette.primaryText
                        )
                        .frame(width: 34, alignment: .trailing)
                }

                HStack(spacing: 4) {
                    Text(subline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    if let hero {
                        Text(compactReset(hero))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(palette.tertiaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var subline: String {
        guard hero != nil else { return "Agent unavailable" }
        guard secondaryWindows.isEmpty == false else { return hero?.label ?? "" }
        return secondaryWindows
            .map { "\($0.label) \($0.displayedPercent.map { "\($0)%" } ?? "—")" }
            .joined(separator: " · ")
    }

    private func compactReset(_ ring: WidgetRingPresentation) -> String {
        WidgetResetPhrasing.compactText(
            WidgetResetPhrasing.phrase(for: ring.resetState, nowEpoch: nowEpoch),
            nowEpoch: nowEpoch
        )
    }

    private var accessibilitySummary: String {
        var parts = [provider.name]
        if let hero {
            let percent = hero.displayedPercent.map { "\($0) percent" } ?? "Not reported"
            parts.append("\(hero.label), \(percent)")
            parts.append(WidgetResetPhrasing.longText(
                WidgetResetPhrasing.phrase(for: hero.resetState, nowEpoch: nowEpoch),
                nowEpoch: nowEpoch
            ))
        } else {
            parts.append("Agent unavailable")
        }
        for window in secondaryWindows {
            let percent = window.displayedPercent.map { "\($0) percent" } ?? "Not reported"
            parts.append("\(window.label), \(percent)")
        }
        return parts.joined(separator: ", ")
    }
}
