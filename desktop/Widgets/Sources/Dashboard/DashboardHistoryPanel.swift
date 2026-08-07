import AgentMeterWidgetCore
import SwiftUI

/// Allowance-consumption strip with its micro caption row, shared by the
/// large dashboard footer and the extra-large right rail.
struct DashboardHistoryPanel: View {
    let history: WidgetHistoryProjection?
    let periodLabel: String
    let accent: Color
    let palette: WidgetThemePalette
    var cellHeight: CGFloat = 8
    var cornerRadius: CGFloat = 3
    var columns: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("ALLOWANCE CONSUMED")
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(palette.tertiaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(periodLabel)
                    .font(.system(size: 8.5))
                    .foregroundStyle(palette.tertiaryText)
                    .lineLimit(1)
            }

            if let history, history.availabilityMessage == nil {
                ConsumptionStrip(
                    cells: history.cells,
                    accent: accent,
                    palette: palette,
                    cellHeight: cellHeight,
                    cornerRadius: cornerRadius,
                    columns: columns
                )
            } else {
                Text(
                    history?.availabilityMessage
                        ?? WidgetPresentationResolver.unavailableHistoryMessage
                )
                .font(.system(size: 9.5))
                .foregroundStyle(palette.tertiaryText)
                .lineLimit(2)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
