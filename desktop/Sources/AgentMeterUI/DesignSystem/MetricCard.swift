import SwiftUI

public struct MetricCard: View {
    private let title: String
    private let value: String
    private let symbol: String
    private let tint: Color

    public init(title: String, value: String, symbol: String, tint: Color = AgentMeterTheme.accent) {
        self.title = title
        self.value = value
        self.symbol = symbol
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .agentMeterCard()
        .accessibilityElement(children: .combine)
    }
}

public struct UsageRing: View {
    private let percent: Int?
    private let tint: Color

    public init(percent: Int?, tint: Color) {
        self.percent = percent
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(AgentMeterTheme.border.opacity(0.75), lineWidth: 7)
            if let percent {
                Circle()
                    .trim(from: 0, to: min(max(CGFloat(percent) / 100, 0), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(percent.map { "\($0)%" } ?? "—")
                .font(.caption.weight(.bold).monospacedDigit())
        }
        .accessibilityLabel(percent.map { "\($0) percent used" } ?? "Usage unavailable")
    }
}
