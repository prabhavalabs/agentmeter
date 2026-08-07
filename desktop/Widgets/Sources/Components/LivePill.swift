import AgentMeterWidgetCore
import SwiftUI

/// Freshness capsule from the v2 design language: "LIVE" in the live green
/// while the snapshot is current, "STALE" in the warn amber otherwise.
struct LivePill: View {
    let freshness: WidgetFreshnessState

    private var color: Color {
        freshness == .fresh ? WidgetV2Tokens.live : WidgetV2Tokens.warn
    }

    private var title: String {
        freshness == .fresh ? "LIVE" : "STALE"
    }

    var body: some View {
        Text(title)
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
            .accessibilityLabel(freshness == .fresh ? "Data current" : "Data stale")
    }
}
