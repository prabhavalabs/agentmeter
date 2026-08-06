import AgentMeterWidgetCore
import SwiftUI

struct DashboardHistorySemantics: Equatable {
    let title: String
    let rangeLabel: String
    let style: WidgetHistoryStyle

    init(presentation: WidgetPresentation) {
        style = presentation.configuration.historyStyle
        rangeLabel = presentation.configuration.historyPeriod.displayLabel
        switch presentation.configuration.historyStyle {
        case .heatMap, .bars:
            if presentation.configuration.heatMapScope == .combined {
                title = "Average allowance consumed"
            } else {
                let provider = presentation.providers.first(where: {
                    $0.availability == .available
                })?.name ?? "Selected provider"
                title = "\(provider) allowance consumed"
            }
        case .trend:
            let window = presentation.history?.windowLabel ?? "Selected window"
            title = "\(window) allowance used"
        case .none:
            title = "Allowance history"
        }
    }
}

struct DashboardHistoryPanel: View {
    let projection: WidgetHistoryProjection
    let semantics: DashboardHistorySemantics
    let lowAccent: Color
    let moderateAccent: Color
    let highAccent: Color
    let veryHighAccent: Color
    let lineAccent: Color
    let pointAccent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(semantics.title, systemImage: historySymbol)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(semantics.rangeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let message = projection.availabilityMessage {
                WidgetStateView(title: message, systemImage: "calendar.badge.exclamationmark")
            } else {
                switch semantics.style {
                case .heatMap, .bars:
                    UsageHeatMap(
                        projection: projection,
                        lowAccent: lowAccent,
                        moderateAccent: moderateAccent,
                        highAccent: highAccent,
                        veryHighAccent: veryHighAccent,
                        showsHeader: false
                    )
                case .trend:
                    UsageTrendChart(
                        projection: projection,
                        lineAccent: lineAccent,
                        pointAccent: pointAccent,
                        showsHeader: false
                    )
                case .none:
                    EmptyView()
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var historySymbol: String {
        semantics.style == .trend ? "chart.xyaxis.line" : "square.grid.3x3.fill"
    }
}
