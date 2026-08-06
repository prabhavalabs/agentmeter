import AgentMeterWidgetCore
import Charts
import SwiftUI

struct UsageTrendChart: View {
    let projection: WidgetHistoryProjection
    let lineAccent: Color
    let pointAccent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Allowance consumption trend", systemImage: "chart.xyaxis.line")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(windowPeriodLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if projection.trendPoints.isEmpty {
                WidgetStateView(
                    title: projection.availabilityMessage ?? "Trend unavailable",
                    systemImage: "chart.line.downtrend.xyaxis"
                )
            } else {
                chart
            }
        }
        .accessibilityRepresentation {
            VStack(alignment: .leading) {
                Text(accessibilitySummary)
                ForEach(Array(projection.trendPoints.enumerated()), id: \.offset) { _, point in
                    Text(WidgetHistoryAccessibility.trendDay(point))
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(samples) { sample in
                LineMark(
                    x: .value("Day", sample.date),
                    y: .value("Used allowance", sample.value),
                    series: .value("Continuous segment", sample.segment)
                )
                .foregroundStyle(lineAccent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Day", sample.date),
                    y: .value("Used allowance", sample.value)
                )
                .foregroundStyle(pointAccent)
                .symbolSize(16)
            }

            ForEach(gaps, id: \.dayStartEpoch) { gap in
                RuleMark(x: .value("Unreported day", gap.date))
                    .foregroundStyle(Color.secondary.opacity(0.28))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel()
            }
        }
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
    }

    private var samples: [TrendSample] {
        var segment = 0
        return projection.trendPoints.compactMap { point in
            guard let value = point.latestUsedPercent else {
                segment += 1
                return nil
            }
            return TrendSample(dayStartEpoch: point.dayStartEpoch, value: value, segment: segment)
        }
    }

    private var gaps: [WidgetTrendPoint] {
        projection.trendPoints.filter { $0.latestUsedPercent == nil }
    }

    private var windowPeriodLabel: String {
        let window = projection.windowLabel ?? "Selected window"
        return "\(window) · \(projection.trendPoints.count) days"
    }

    private var accessibilitySummary: String {
        let values = projection.trendPoints.compactMap(\.latestUsedPercent)
        let latest = values.last.map { "latest \($0) percent used" } ?? "latest value not reported"
        return "\(projection.windowLabel ?? "Selected window") allowance consumption trend, \(latest), \(projection.trendPoints.count - values.count) gaps"
    }
}

private struct TrendSample: Identifiable {
    let dayStartEpoch: Int
    let value: Int
    let segment: Int

    var id: Int { dayStartEpoch }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(dayStartEpoch)) }
}

private extension WidgetTrendPoint {
    var date: Date { Date(timeIntervalSince1970: TimeInterval(dayStartEpoch)) }
}
