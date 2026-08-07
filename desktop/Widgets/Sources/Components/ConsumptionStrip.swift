import AgentMeterWidgetCore
import SwiftUI

/// Daily allowance-consumption cells from the v2 design language. A single
/// flexible-width row by default, or a fixed-column grid for the XL rail.
struct ConsumptionStrip: View {
    let cells: [WidgetHeatMapCell]
    let accent: Color
    let palette: WidgetThemePalette
    var cellHeight: CGFloat = 8
    var cornerRadius: CGFloat = 3
    var columns: Int? = nil

    var body: some View {
        Group {
            if let columns {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns),
                    spacing: 4
                ) {
                    cellViews
                }
            } else {
                HStack(spacing: 3) {
                    cellViews
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var cellViews: some View {
        ForEach(cells, id: \.dayStartEpoch) { cell in
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill(for: cell))
                .frame(maxWidth: .infinity)
                .frame(height: cellHeight)
        }
    }

    private func fill(for cell: WidgetHeatMapCell) -> Color {
        guard cell.hasData else { return palette.track.opacity(0.5) }
        switch cell.band {
        case .zero, nil: return palette.track
        case .low: return accent.opacity(0.35)
        case .moderate: return accent.opacity(0.55)
        case .high: return accent.opacity(0.7)
        case .veryHigh: return accent
        }
    }

    private var accessibilitySummary: String {
        let reported = cells.filter(\.hasData).count
        return "Allowance consumed over \(cells.count) days, \(reported) days reported"
    }
}
