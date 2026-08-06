import AgentMeterWidgetCore
import SwiftUI

enum WidgetHealthSemantics {
    static func mandatoryLabels(
        provider: WidgetProviderPresentation,
        freshness: WidgetFreshnessState
    ) -> [String] {
        var labels = providerLabel(provider).map { [$0] } ?? []
        if freshness == .stale, labels.contains("Stale") == false {
            labels.append("Stale")
        }
        return labels
    }

    static func providerLabel(_ provider: WidgetProviderPresentation) -> String? {
        if provider.availability == .missing { return "Agent unavailable" }
        switch provider.healthState {
        case .healthy:
            return nil
        case .stale:
            return "Stale"
        case .error:
            return "Agent error"
        case .unavailable:
            return "Agent unavailable"
        case .attention:
            return "Needs attention"
        }
    }

    static func freshnessLabel(_ freshness: WidgetFreshnessState) -> String? {
        freshness == .stale ? "Stale" : nil
    }
}

struct WidgetHealthBadges: View {
    let labels: [String]
    var compact = false

    var accessibilitySummary: String {
        labels.joined(separator: ", ")
    }

    @ViewBuilder
    var body: some View {
        if labels.isEmpty == false {
            if compact {
                HStack(spacing: 4) {
                    ForEach(labels, id: \.self) { label in
                        Image(systemName: symbol(for: label))
                            .accessibilityHidden(true)
                    }
                }
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .foregroundStyle(.primary)
                .background(Color.orange.opacity(0.2), in: Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary)
            } else {
                HStack(spacing: 4) {
                    ForEach(labels, id: \.self) { label in
                        Label(label, systemImage: symbol(for: label))
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .foregroundStyle(.primary)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                            .accessibilityLabel(label)
                    }
                }
            }
        }
    }

    private func symbol(for label: String) -> String {
        label == "Stale" ? "clock.badge.exclamationmark" : "exclamationmark.triangle.fill"
    }
}
