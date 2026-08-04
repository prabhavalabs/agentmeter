import AgentMeterUI
import AppKit
import Testing

@MainActor
@Test func closingLastWindowEntersMenuBarOnlyMode() {
    let application = TestApplicationActivationClient(policy: .regular)
    let controller = ApplicationPresentationController(application: application)

    controller.lastWindowDidClose()

    #expect(application.activationPolicy == .accessory)
    #expect(application.activationCount == 0)
}

@MainActor
@Test func openingWindowRestoresDockAndActivatesApplication() {
    let application = TestApplicationActivationClient(policy: .accessory)
    let controller = ApplicationPresentationController(application: application)

    controller.windowWillOpen()

    #expect(application.activationPolicy == .regular)
    #expect(application.activationCount == 1)
}

@MainActor
private final class TestApplicationActivationClient: ApplicationActivationClient {
    private(set) var activationPolicy: NSApplication.ActivationPolicy
    private(set) var activationCount = 0

    init(policy: NSApplication.ActivationPolicy) {
        activationPolicy = policy
    }

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        self.activationPolicy = activationPolicy
        return true
    }

    func activate(ignoringOtherApps flag: Bool) {
        activationCount += 1
    }
}
