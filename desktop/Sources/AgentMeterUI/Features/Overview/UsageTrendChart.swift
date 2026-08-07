import AgentMeterCore
import Charts
import SwiftUI

struct UsageTrendChart: View {
    let range: UsageHistoryRange
    let onSelectRange: @MainActor @Sendable (UsageHistoryRange) -> Void

    private let series: [TrendSeries]
    private let now: Date

    init(
        samples: [UsageHistorySample],
        providers: [ProviderSummary],
        range: UsageHistoryRange,
        now: Date = .now,
        onSelectRange: @escaping @MainActor @Sendable (UsageHistoryRange) -> Void
    ) {
        self.range = range
        self.now = now
        self.onSelectRange = onSelectRange
        series = providers.compactMap { provider in
            // Chart the long allowance window: session windows reset every few
            // hours and draw a sawtooth that reads as erratic usage.
            let preferredKind = provider.windows.first(where: { $0.kind == "weekly" })?.kind
                ?? provider.windows.first(where: { $0.kind != "session" })?.kind
                ?? provider.windows.first?.kind
            guard let preferredKind else { return nil }
            let matching = samples
                .filter {
                    $0.providerId == provider.id
                        && $0.windowKind == preferredKind
                        && $0.usedPercent != nil
                }
                .sorted { $0.sampledAtEpoch < $1.sampledAtEpoch }
            guard matching.isEmpty == false else { return nil }
            return TrendSeries(
                id: provider.id,
                name: provider.name,
                color: ProviderPalette.accent(for: provider.id),
                samples: matching
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if series.isEmpty {
                ContentUnavailableView(
                    "No history for this range",
                    systemImage: "chart.xyaxis.line",
                    description: Text("AgentMeter will add points as local usage samples arrive.")
                )
                .frame(maxWidth: .infinity, minHeight: 190)
            } else {
                chart
                legend
            }
        }
        .padding(18)
        .agentMeterCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent usage trends, \(range.title)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(range.title)
                        .font(.headline)
                    Text(rangeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("Local only", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker(
                "History range",
                selection: Binding(
                    get: { range },
                    set: { onSelectRange($0) }
                )
            ) {
                ForEach(UsageHistoryRange.allCases) { option in
                    Text(option.compactTitle).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 360)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(series) { item in
                ForEach(item.samples) { sample in
                    if let percent = sample.usedPercent {
                        let date = Date(
                            timeIntervalSince1970: Double(sample.sampledAtEpoch)
                        )
                        LineMark(
                            x: .value("Time", date),
                            y: .value("Usage", percent),
                            series: .value("Agent", item.id)
                        )
                        .foregroundStyle(item.color)
                        .interpolationMethod(.monotone)

                        PointMark(
                            x: .value("Time", date),
                            y: .value("Usage", percent)
                        )
                        .foregroundStyle(item.color)
                        .symbolSize(16)
                    }
                }
            }
        }
        .chartXScale(domain: chartDomain)
        .chartYScale(domain: 0 ... 100)
        // Marks are not clipped to the plot area by default, so a point that
        // lands on the domain boundary spills over the axis labels.
        .chartPlotStyle { plotArea in
            plotArea.clipped()
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Int.self) { Text("\(percent)%") }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        axisLabel(for: date)
                    }
                }
            }
        }
        .frame(height: 210)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            ForEach(series) { item in
                Label {
                    Text(item.name)
                } icon: {
                    Circle().fill(item.color).frame(width: 8, height: 8)
                }
                .font(.caption)
            }
        }
    }

    private var rangeDescription: String {
        switch range {
        case .last24Hours:
            "24 hourly buckets. Gaps indicate that no local sample was stored."
        case .last7Days:
            "Seven daily buckets. Gaps indicate that no local sample was stored."
        case .last30Days:
            "Thirty daily buckets. Gaps indicate that no local sample was stored."
        case .currentCycle:
            "Usage since the latest reset observed locally, or since history began."
        }
    }

    private var chartDomain: ClosedRange<Date> {
        if range == .currentCycle, let first = series.flatMap(\.samples).first {
            let earliest = series
                .flatMap(\.samples)
                .map(\.sampledAtEpoch)
                .min() ?? first.sampledAtEpoch
            return Date(timeIntervalSince1970: Double(earliest)) ... now
        }
        let start = Date(
            timeIntervalSince1970: Double(range.query(now: now).sinceEpoch)
        )
        return start ... now
    }

    private var axisDates: [Date] {
        let start = chartDomain.lowerBound
        switch range {
        case .last24Hours:
            return dates(from: start, component: .hour, offsets: [0, 4, 8, 12, 16, 20])
        case .last7Days:
            return dates(from: start, component: .day, offsets: Array(0 ... 5))
        case .last30Days:
            return dates(from: start, component: .day, offsets: [0, 5, 10, 15, 20, 25])
        case .currentCycle:
            let duration = max(1, chartDomain.upperBound.timeIntervalSince(start))
            return (0 ..< 5).map { index in
                start.addingTimeInterval(duration * Double(index) / 5)
            }
        }
    }

    private func dates(
        from start: Date,
        component: Calendar.Component,
        offsets: [Int]
    ) -> [Date] {
        offsets.compactMap { Calendar.current.date(byAdding: component, value: $0, to: start) }
    }

    @ViewBuilder
    private func axisLabel(for date: Date) -> some View {
        switch range {
        case .last24Hours:
            Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        case .last7Days, .last30Days:
            Text(date, format: .dateTime.day().month(.abbreviated))
        case .currentCycle:
            if chartDomain.upperBound.timeIntervalSince(chartDomain.lowerBound) > 2 * 86_400 {
                Text(date, format: .dateTime.day().month(.abbreviated))
            } else {
                Text(date, format: .dateTime.hour().minute())
            }
        }
    }
}

private extension UsageHistoryRange {
    var compactTitle: String {
        switch self {
        case .last24Hours: "24H"
        case .last7Days: "7D"
        case .last30Days: "30D"
        case .currentCycle: "Cycle"
        }
    }
}

private struct TrendSeries: Identifiable {
    let id: String
    let name: String
    let color: Color
    let samples: [UsageHistorySample]
}
