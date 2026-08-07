import Testing
@testable import AgentMeterUI

@Test func settingsSectionSitsAtTheBottomOfTheSidebarOrder() {
    #expect(NavigationSection.allCases.last == .settings)
    #expect(NavigationSection.settings.title == "Settings")
    #expect(NavigationSection.settings.symbolName == "gearshape")
}

@Test func visibleSectionsKeepEverySectionWhileDeviceSyncIsOn() {
    #expect(
        NavigationSection.visibleSections(deviceSyncEnabled: true)
            == NavigationSection.allCases
    )
}

@Test func standaloneModeHidesDeviceAndDisplaySectionsOnly() {
    let visible = NavigationSection.visibleSections(deviceSyncEnabled: false)

    #expect(visible == [.overview, .agents, .diagnostics, .settings])
    #expect(visible.contains(.device) == false)
    #expect(visible.contains(.display) == false)
}

@Test func onlyDeviceScopedSectionsRequireDeviceSync() {
    #expect(NavigationSection.allCases.filter(\.requiresDeviceSync) == [.device, .display])
}

@Test func hiddenSelectionsFallBackToOverviewInStandaloneMode() {
    #expect(NavigationSection.resolvedSelection(.device, deviceSyncEnabled: false) == .overview)
    #expect(NavigationSection.resolvedSelection(.display, deviceSyncEnabled: false) == .overview)
    #expect(NavigationSection.resolvedSelection(.settings, deviceSyncEnabled: false) == .settings)
    #expect(NavigationSection.resolvedSelection(.agents, deviceSyncEnabled: false) == .agents)
    for section in NavigationSection.allCases {
        #expect(NavigationSection.resolvedSelection(section, deviceSyncEnabled: true) == section)
    }
}
