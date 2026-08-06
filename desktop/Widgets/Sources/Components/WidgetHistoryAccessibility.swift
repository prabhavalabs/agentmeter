import AgentMeterWidgetCore
import Foundation

enum WidgetHistoryAccessibility {
    static func heatMapDay(_ cell: WidgetHeatMapCell) -> String {
        let date = formattedDate(cell.dayStartEpoch)
        guard let value = cell.value else {
            return "\(date), No allowance consumption reported"
        }
        let number = value.formatted(.number.precision(.fractionLength(0...1)))
        return "\(date), \(number) allowance percentage points consumed"
    }

    static func trendDay(_ point: WidgetTrendPoint) -> String {
        let date = formattedDate(point.dayStartEpoch)
        guard let value = point.latestUsedPercent else {
            return "\(date), Used allowance not reported"
        }
        return "\(date), \(value) percent used"
    }

    private static func formattedDate(_ epoch: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(epoch)).formatted(
            date: .abbreviated,
            time: .omitted
        )
    }
}
