import Foundation
import Testing
@testable import AgentMeterCore

private enum Fixture {
    static func data(named name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "Fixtures"
            )
        )
        return try Data(contentsOf: url)
    }
}

@Test func statusFixturePreservesUnavailableBatteryValues() throws {
    let data = try Fixture.data(named: "desktop-ipc-status-v1")
    let envelope = try JSONDecoder().decode(StatusEnvelope.self, from: data)

    #expect(envelope.payload.connection.phase == .connected)
    #expect(envelope.payload.telemetry?.batteryPresent == false)
    #expect(envelope.payload.telemetry?.batteryPercent == nil)
    #expect(envelope.payload.telemetry?.inputCurrentMa == nil)
    #expect(envelope.payload.providers.first?.windows.first?.usedPercent == 28)
    #expect(envelope.payload.bridge.configuredProviderIds == ["codex", "claude", "gemini", "cursor"])
    #expect(envelope.payload.bridge.pollIntervalSeconds == 300)
}

@Test func everyConnectionPhaseDecodesFromItsWireValue() throws {
    for phase in ConnectionPhase.allCases {
        let data = Data("\"\(phase.rawValue)\"".utf8)
        #expect(try JSONDecoder().decode(ConnectionPhase.self, from: data) == phase)
    }
}

@Test func decodesWidgetHistorySummaryDayFields() throws {
    let data = Data(
        """
        {
          "historyStartEpoch": 1788249600,
          "days": [
            {
              "providerId": "claude",
              "windowKind": "session",
              "dayStartEpoch": 1788242400,
              "consumedPercentPoints": 17,
              "latestUsedPercent": 28,
              "resetAtEpoch": 1788336000
            }
          ]
        }
        """.utf8
    )

    let summary = try JSONDecoder().decode(WidgetHistorySummary.self, from: data)
    let day = try #require(summary.days.first)

    #expect(summary.historyStartEpoch == 1_788_249_600)
    #expect(day.providerId == "claude")
    #expect(day.windowKind == "session")
    #expect(day.dayStartEpoch == 1_788_242_400)
    #expect(day.consumedPercentPoints == 17)
    #expect(day.latestUsedPercent == 28)
    #expect(day.resetAtEpoch == 1_788_336_000)
}

@Test func decodesWidgetHistorySummaryOptionalNulls() throws {
    let data = Data(
        """
        {
          "historyStartEpoch": null,
          "days": [
            {
              "providerId": "claude",
              "windowKind": "weekly",
              "dayStartEpoch": 1788242400,
              "consumedPercentPoints": 0,
              "latestUsedPercent": null,
              "resetAtEpoch": null
            }
          ]
        }
        """.utf8
    )

    let summary = try JSONDecoder().decode(WidgetHistorySummary.self, from: data)
    let day = try #require(summary.days.first)

    #expect(summary.historyStartEpoch == nil)
    #expect(day.latestUsedPercent == nil)
    #expect(day.resetAtEpoch == nil)
}
