import AgentMeterWidgetCore
import SwiftUI

/// Small glowing health dot from the v2 design language. Green while healthy,
/// amber under allowance pressure, red on agent errors, grey when the data is
/// stale or the agent is unavailable.
struct StatusDot: View {
    let health: WidgetProviderHealthState
    let worstUsedPercent: Int?
    var size: CGFloat = 7
    var glows = true

    private var dotColor: Color {
        switch health {
        case .error:
            return Color(red: 0.847, green: 0.341, blue: 0.29)
        case .stale, .unavailable:
            return Color.secondary.opacity(0.5)
        case .healthy, .attention:
            return (worstUsedPercent ?? 0) >= 75 ? WidgetV2Tokens.warn : WidgetV2Tokens.live
        }
    }

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: size, height: size)
            .shadow(
                color: glows ? dotColor.opacity(0.6) : .clear,
                radius: glows ? 3 : 0
            )
            .accessibilityHidden(true)
    }
}
