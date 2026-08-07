import AgentMeterWidgetCore
import Charts
import SwiftUI

/// Daily usage trend line for the Focus history module, drawn in the v2
/// visual language: a single accent line over a hidden axis grid with a
/// bottom rule.
struct UsageTrendChart: View {
    let trendPoints: [WidgetTrendPoint]
    let accent: Color
    let palette: WidgetThemePalette
    var height: CGFloat = 46
    var lineWidth: CGFloat = 1.6

    var body: some View {
        Chart {
            ForEach(samples, id: \.dayStartEpoch) { sample in
                LineMark(
                    x: .value(
                        "Day",
                        Date(timeIntervalSince1970: TimeInterval(sample.dayStartEpoch))
                    ),
                    y: .value("Used", sample.value)
                )
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: height)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.rule)
                .frame(height: 1)
        }
        .accessibilityRepresentation {
            VStack(alignment: .leading) {
                Text(accessibilitySummary)
                ForEach(Array(trendPoints.enumerated()), id: \.offset) { _, point in
                    Text(WidgetHistoryAccessibility.trendDay(point))
                }
            }
        }
    }

    private var samples: [(dayStartEpoch: Int, value: Int)] {
        trendPoints.compactMap { point in
            point.latestUsedPercent.map { (point.dayStartEpoch, $0) }
        }
    }

    private var accessibilitySummary: String {
        let values = trendPoints.compactMap(\.latestUsedPercent)
        let latest = values.last.map { "latest \($0) percent used" } ?? "latest value not reported"
        return "Allowance consumption trend, \(latest), \(trendPoints.count - values.count) gaps"
    }
}
