import AgentMeterCore
import SwiftUI

public struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(BridgeServiceController.self) private var bridgeService
    @Environment(WorkspacePowerObserver.self) private var powerObserver
    @Environment(UserNotificationController.self) private var notifications

    public init() {}

    public var body: some View {
        @Bindable var preferences = model.preferences
        NavigationSplitView {
            Sidebar(
                selection: $preferences.selectedSection,
                sections: NavigationSection.visibleSections(
                    deviceSyncEnabled: model.deviceSyncEnabled
                )
            )
        } detail: {
            destination
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AgentMeterTheme.windowBackground)
        }
        .frame(minWidth: 900, minHeight: 620)
        .task {
            model.stateEventHandler = { [weak notifications] event, previous, current in
                notifications?.process(
                    eventId: event.id,
                    previous: previous,
                    current: current,
                    enabled: model.preferences.notificationsEnabled
                )
            }
            if model.preferences.notificationsEnabled {
                _ = await notifications.setEnabled(true)
            }
            await bridgeService.start()
            await model.start(showFailure: bridgeService.state != .waitingForBridge)
            if model.bridgeReachable { bridgeService.confirmBridgeReady() }
        }
        .onChange(of: model.bridgeReachable) { _, reachable in
            if reachable { bridgeService.confirmBridgeReady() }
        }
        .onChange(of: model.deviceSyncEnabled, initial: true) { _, enabled in
            model.selectedSection = NavigationSection.resolvedSelection(
                model.selectedSection,
                deviceSyncEnabled: enabled
            )
        }
        .sheet(
            isPresented: Binding(
                get: { model.preferences.onboardingComplete == false },
                set: { _ in }
            )
        ) {
            OnboardingView()
        }
        .onAppear { powerObserver.start(model: model) }
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
        case .settings: ApplicationSettingsSectionView()
        }
    }
}
