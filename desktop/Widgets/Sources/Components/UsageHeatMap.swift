import AgentMeterWidgetCore
import SwiftUI

struct UsageHeatMap: View {
    let projection: WidgetHistoryProjection
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Allowance consumption", systemImage: "square.grid.3x3.fill")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(periodLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if projection.cells.isEmpty {
                WidgetStateView(
                    title: projection.availabilityMessage ?? "History unavailable",
                    systemImage: "calendar.badge.exclamationmark"
                )
            } else {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(Array(projection.cells.enumerated()), id: \.offset) { _, cell in
                        HeatMapCell(cell: cell, accent: accent)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .accessibilityRepresentation {
            VStack(alignment: .leading) {
                Text(accessibilitySummary)
                ForEach(Array(projection.cells.enumerated()), id: \.offset) { _, cell in
                    Text(WidgetHistoryAccessibility.heatMapDay(cell))
                }
            }
        }
    }

    private var columns: [GridItem] {
        let count = projection.cells.count > 7 ? 10 : max(1, projection.cells.count)
        return Array(repeating: GridItem(.flexible(minimum: 4), spacing: 3), count: count)
    }

    private var periodLabel: String {
        "Last \(projection.cells.count) days"
    }

    private var accessibilitySummary: String {
        let available = projection.cells.filter(\.hasData).count
        return "Allowance consumption heat map, \(available) of \(projection.cells.count) days reported"
    }
}

private struct HeatMapCell: View {
    let cell: WidgetHeatMapCell
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(fill)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .strokeBorder(border, lineWidth: cell.hasData ? 0.6 : 1)

            if cell.hasData == false {
                Rectangle()
                    .fill(Color.secondary.opacity(0.55))
                    .frame(height: 1)
                    .rotationEffect(.degrees(-35))
                    .padding(2)
            } else if cell.band == .zero {
                Circle()
                    .fill(Color.secondary.opacity(0.7))
                    .frame(width: 2.5, height: 2.5)
            }
        }
    }

    private var fill: Color {
        switch cell.band {
        case .zero: return Color.secondary.opacity(0.08)
        case .low: return accent.opacity(0.22)
        case .moderate: return accent.opacity(0.4)
        case .high: return accent.opacity(0.65)
        case .veryHigh: return accent.opacity(0.92)
        case nil: return Color.clear
        }
    }

    private var border: Color {
        cell.hasData ? accent.opacity(0.22) : Color.secondary.opacity(0.45)
    }
}
