import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class WorkspacePowerObserver {
    @ObservationIgnored nonisolated(unsafe) private var sleepTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var wakeTask: Task<Void, Never>?

    public init() {}

    public func start(model: AppModel) {
        guard sleepTask == nil, wakeTask == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        sleepTask = Task { [weak model] in
            for await _ in center.notifications(named: NSWorkspace.willSleepNotification) {
                guard Task.isCancelled == false else { return }
                await model?.systemWillSleep()
            }
        }
        wakeTask = Task { [weak model] in
            for await _ in center.notifications(named: NSWorkspace.didWakeNotification) {
                guard Task.isCancelled == false else { return }
                await model?.systemDidWake()
            }
        }
    }

    public func stop() {
        sleepTask?.cancel()
        sleepTask = nil
        wakeTask?.cancel()
        wakeTask = nil
    }

    deinit {
        sleepTask?.cancel()
        wakeTask?.cancel()
    }
}
