import SwiftUI
import WidgetKit

@main
struct AgentMeterWidgetBundle: WidgetBundle {
    var body: some Widget {
        AgentMeterDashboardWidget()
        AgentMeterFocusWidget()
    }
}
