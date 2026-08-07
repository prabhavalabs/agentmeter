import AgentMeterCore
import AgentMeterWidgetCore
import Charts
import SwiftUI

/// One provider's 24-hour usage line for the dashboard trend module.
struct HourlyTrendSeries: Identifiable {
    let id: String
    let name: String
    let accent: Color
    let points: [WidgetHourlyPoint]
}

/// Multi-provider hourly usage chart from the v2 design language.
struct HourlyTrendChart: View {
    let series: [HourlyTrendSeries]
    let palette: WidgetThemePalette
    var height: CGFloat = 46
    var showsYAxis = false
    var lineWidth: CGFloat = 1.6

    var body: some View {
        chart
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var chart: some View {
        if showsYAxis {
            baseChart
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(palette.rule)
                        AxisValueLabel()
                            .font(.system(size: 8))
                            .foregroundStyle(palette.tertiaryText)
                    }
                }
        } else {
            baseChart
                .chartYAxis(.hidden)
        }
    }

    private var baseChart: some View {
        Chart {
            ForEach(series) { line in
                ForEach(line.points, id: \.hourStartEpoch) { point in
                    LineMark(
                        x: .value(
                            "Hour",
                            Date(timeIntervalSince1970: TimeInterval(point.hourStartEpoch))
                        ),
                        y: .value("Used", point.latestUsedPercent),
                        series: .value("Agent", line.id)
                    )
                    .foregroundStyle(line.accent)
                    .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }
        }
    }

    private var accessibilitySummary: String {
        let names = series.map(\.name).joined(separator: ", ")
        return "Last 24 hours allowance trend for \(names)"
    }
}
