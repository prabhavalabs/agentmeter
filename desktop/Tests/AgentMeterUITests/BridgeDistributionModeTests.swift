import AgentMeterUI
import Testing

@Test func communityDistributionModeIsExplicit() {
    #expect(BridgeDistributionMode.resolve(plistValue: "community") == .community)
    #expect(BridgeDistributionMode.resolve(plistValue: "developer") == .managed)
    #expect(BridgeDistributionMode.resolve(plistValue: nil) == .managed)
}
