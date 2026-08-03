import Testing
@testable import AgentMeterUI

@Test func rotationIntervalOptionsKeepTheCurrentDeviceValueVisible() {
    #expect(DisplaySettingsControlPolicy.rotationOptions(current: 6) == [3, 5, 6, 10, 15])
}
