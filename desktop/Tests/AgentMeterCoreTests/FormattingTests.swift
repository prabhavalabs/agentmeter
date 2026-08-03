import Testing
@testable import AgentMeterCore

@Test func usageFormattingKeepsUnknownValuesExplicit() {
    #expect(UsageFormatting.percentage(nil) == "Unavailable")
    #expect(UsageFormatting.percentage(42) == "42%")
    #expect(UsageFormatting.percentage(101) == "Unavailable")
}

@Test func countdownFormattingUsesAStableReferenceTime() {
    #expect(
        UsageFormatting.resetCountdown(resetAtEpoch: 10_000, nowEpoch: 1_960)
            == "Resets in 2h 14m"
    )
    #expect(UsageFormatting.updatedAge(updatedAtEpoch: 1_800, nowEpoch: 2_000) == "Updated 3m ago")
}

@Test func telemetryFormattingNeverInventsBatteryData() {
    #expect(TelemetryFormatting.powerSource("usb") == "USB")
    #expect(TelemetryFormatting.battery(present: false, percent: nil) == "Not installed")
    #expect(TelemetryFormatting.battery(present: true, percent: nil) == "Unavailable")
    #expect(TelemetryFormatting.battery(present: true, percent: 42) == "42%")
}
