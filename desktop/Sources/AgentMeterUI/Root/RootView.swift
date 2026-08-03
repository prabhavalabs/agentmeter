import AgentMeterCore
import SwiftUI

public struct RootView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        NavigationSplitView {
            Sidebar()
        } detail: {
            destination
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AgentMeterTheme.windowBackground)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        StatusPill(
                            model.state.connection.phase.displayName,
                            symbol: model.state.connection.phase.symbolName,
                            tint: model.state.connection.phase.tint
                        )
                        Button {
                            Task { await model.refreshProviders() }
                        } label: {
                            Label("Refresh usage", systemImage: "arrow.clockwise")
                        }
                        .disabled(model.activeOperations.contains(.providerRefresh))
                        .help("Refresh coding-agent usage")
                    }
                }
        }
        .frame(minWidth: 900, minHeight: 620)
        .task { await model.start() }
        .alert(
            model.notice?.title ?? "AgentMeter",
            isPresented: Binding(
                get: { model.notice != nil },
                set: { if !$0 { model.dismissNotice() } }
            ),
            presenting: model.notice
        ) { _ in
            Button("OK") { model.dismissNotice() }
        } message: { notice in
            Text(notice.message)
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch model.selectedSection {
        case .overview: OverviewView()
        case .device: DeviceView()
        case .agents: AgentsView()
        case .display: DisplaySettingsView()
        case .diagnostics: DiagnosticsView()
        }
    }
}
