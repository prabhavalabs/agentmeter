import AgentMeterWidgetCore
import SwiftUI

struct UsageHeatMapLayout: Equatable {
    let cellCount: Int
    let compact: Bool

    var columnCount: Int {
        guard cellCount > 0 else { return 1 }
        if compact { return min(cellCount, 30) }
        return cellCount > 7 ? 10 : cellCount
    }

    var rowCount: Int {
        guard cellCount > 0 else { return 0 }
        return Int(ceil(Double(cellCount) / Double(columnCount)))
    }
}

struct UsageHeatMap: View {
    let projection: WidgetHistoryProjection
    let lowAccent: Color
    let moderateAccent: Color
    let highAccent: Color
    let veryHighAccent: Color
    var showsHeader = true
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 7) {
            if showsHeader {
                HStack {
                    Label("Allowance consumption", systemImage: "square.grid.3x3.fill")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(periodLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if projection.cells.isEmpty {
                WidgetStateView(
                    title: projection.availabilityMessage ?? "History unavailable",
                    systemImage: "calendar.badge.exclamationmark"
                )
            } else {
                LazyVGrid(columns: columns, spacing: compact ? 2 : 3) {
                    ForEach(Array(projection.cells.enumerated()), id: \.offset) { _, cell in
                        HeatMapCell(
                            cell: cell,
                            lowAccent: lowAccent,
                            moderateAccent: moderateAccent,
                            highAccent: highAccent,
                            veryHighAccent: veryHighAccent
                        )
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
        let layout = UsageHeatMapLayout(cellCount: projection.cells.count, compact: compact)
        let spacing: CGFloat = compact ? 2 : 3
        return Array(
            repeating: GridItem(.flexible(minimum: 4), spacing: spacing),
            count: layout.columnCount
        )
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
    let lowAccent: Color
    let moderateAccent: Color
    let highAccent: Color
    let veryHighAccent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(fill)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .strokeBorder(border, lineWidth: cell.hasData ? 0.6 : 1)

            if let positiveAccent, let positiveScale {
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(positiveAccent)
                        .frame(
                            width: max(2, geometry.size.width * positiveScale),
                            height: max(2, geometry.size.height * positiveScale)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(1.5)
            } else if cell.hasData == false {
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
        case .low, .moderate, .high, .veryHigh: return Color.clear
        case nil: return Color.clear
        }
    }

    private var border: Color {
        if let positiveAccent {
            return positiveAccent
        }
        return Color.secondary.opacity(cell.hasData ? 0.3 : 0.45)
    }

    private var positiveAccent: Color? {
        switch cell.band {
        case .low: lowAccent
        case .moderate: moderateAccent
        case .high: highAccent
        case .veryHigh: veryHighAccent
        case .zero, nil: nil
        }
    }

    private var positiveScale: CGFloat? {
        switch cell.band {
        case .low: 0.28
        case .moderate: 0.46
        case .high: 0.68
        case .veryHigh: 0.92
        case .zero, nil: nil
        }
    }
}
