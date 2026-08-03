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
}

@Test func everyConnectionPhaseDecodesFromItsWireValue() throws {
    for phase in ConnectionPhase.allCases {
        let data = Data("\"\(phase.rawValue)\"".utf8)
        #expect(try JSONDecoder().decode(ConnectionPhase.self, from: data) == phase)
    }
}
