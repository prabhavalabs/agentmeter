import AppKit

@MainActor
public protocol ApplicationActivationClient: AnyObject {
    @discardableResult
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool
    func activate(ignoringOtherApps flag: Bool)
}

extension NSApplication: ApplicationActivationClient {}

@MainActor
public final class ApplicationPresentationController {
    public static let shared = ApplicationPresentationController(application: NSApplication.shared)

    private let application: any ApplicationActivationClient

    public init(application: any ApplicationActivationClient) {
        self.application = application
    }

    public func lastWindowDidClose() {
        application.setActivationPolicy(.accessory)
    }

    public func windowWillOpen() {
        application.setActivationPolicy(.regular)
        application.activate(ignoringOtherApps: true)
    }
}
