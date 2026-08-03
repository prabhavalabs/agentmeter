import AgentMeterCore
import Charts
import SwiftUI

struct UsageTrendChart: View {
    let samples: [UsageHistorySample]
    let providers: [ProviderSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Last 24 hours")
                        .font(.headline)
                    Text("Session usage is sampled locally in five-minute buckets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("Local only", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(series) { item in
                    ForEach(item.samples) { sample in
                        if let percent = sample.usedPercent {
                            LineMark(
                                x: .value("Time", Date(timeIntervalSince1970: Double(sample.sampledAtEpoch))),
                                y: .value("Usage", percent),
                                series: .value("Agent", item.id)
                            )
                            .foregroundStyle(item.color)
                            .interpolationMethod(.monotone)

                            PointMark(
                                x: .value("Time", Date(timeIntervalSince1970: Double(sample.sampledAtEpoch))),
                                y: .value("Usage", percent)
                            )
                            .foregroundStyle(item.color)
                            .symbolSize(16)
                        }
                    }
                }
            }
            .chartYScale(domain: 0 ... 100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let percent = value.as(Int.self) { Text("\(percent)%") }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .frame(height: 190)

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
        .padding(18)
        .agentMeterCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent usage trends for the last 24 hours")
    }

    private var series: [TrendSeries] {
        providers.compactMap { provider in
            let preferredKind = provider.windows.first(where: { $0.kind == "session" })?.kind
                ?? provider.windows.first?.kind
            guard let preferredKind else { return nil }
            let matching = samples.filter {
                $0.providerId == provider.id
                    && $0.windowKind == preferredKind
                    && $0.usedPercent != nil
            }
            guard matching.count >= 2 else { return nil }
            return TrendSeries(
                id: provider.id,
                name: provider.name,
                color: ProviderPalette.accent(for: provider.id),
                samples: matching
            )
        }
    }
}

private struct TrendSeries: Identifiable {
    let id: String
    let name: String
    let color: Color
    let samples: [UsageHistorySample]
}
