import AgentMeterCore
import AgentMeterUI
import Foundation
import Testing

@MainActor
@Test func notificationsAreOptInAndDeduplicated() async {
    let suite = "AgentMeterNotificationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let delivery = FakeNotificationDelivery()
    let controller = UserNotificationController(defaults: defaults, delivery: delivery)
    let previous = notificationState(revision: 1, percent: 65)
    let current = notificationState(revision: 2, percent: 75)

    controller.process(eventId: "event-2", previous: previous, current: current, enabled: true)
    #expect(delivery.plans.isEmpty)
    #expect(delivery.authorizationRequests == 0)

    #expect(await controller.setEnabled(true))
    #expect(delivery.authorizationRequests == 1)
    controller.process(eventId: "event-2", previous: previous, current: current, enabled: true)
    controller.process(eventId: "event-2", previous: previous, current: current, enabled: true)
    await drainNotificationTasks()

    #expect(delivery.plans.count == 1)
    #expect(delivery.plans.first?.kind == .threshold)
    #expect(delivery.plans.first?.title == "Claude usage reached 75%")
}

@MainActor
@Test func lostConnectionWaitsOneMinuteAndReconnectCancelsIt() async {
    let delivery = FakeNotificationDelivery()
    let controller = UserNotificationController(
        defaults: UserDefaults(suiteName: "AgentMeterNotificationTests.\(UUID().uuidString)")!,
        delivery: delivery
    )
    #expect(await controller.setEnabled(true))
    let connected = notificationState(revision: 1, percent: 20, phase: .connected)
    let lost = notificationState(revision: 2, percent: 20, phase: .retrying)

    controller.process(eventId: "lost-2", previous: connected, current: lost, enabled: true)
    await drainNotificationTasks()
    #expect(delivery.plans.first?.delaySeconds == 60)

    controller.process(eventId: "back-3", previous: lost, current: connected, enabled: true)
    #expect(delivery.removed == ["lost-2:connection-lost"])
}

@MainActor
@Test func recentNotificationIdsRemainBounded() async {
    let suite = "AgentMeterNotificationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let delivery = FakeNotificationDelivery()
    let controller = UserNotificationController(defaults: defaults, delivery: delivery)
    #expect(await controller.setEnabled(true))
    let previous = notificationState(revision: 1, percent: 65)
    let current = notificationState(revision: 2, percent: 75)

    for index in 0 ..< 80 {
        controller.process(
            eventId: "threshold-\(index)",
            previous: previous,
            current: current,
            enabled: true
        )
    }

    #expect(defaults.stringArray(forKey: "recentNotificationEventIds")?.count == 64)
}

@MainActor
private final class FakeNotificationDelivery: UserNotificationDelivering {
    var authorizationRequests = 0
    var authorizationResult = true
    var permission = NotificationPermissionState.notDetermined
    var plans: [PlannedNotification] = []
    var removed: [String] = []

    func permissionState() async -> NotificationPermissionState {
        permission
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        return authorizationResult
    }

    func add(_ plan: PlannedNotification) async throws {
        plans.append(plan)
    }

    func removePending(identifiers: [String]) {
        removed.append(contentsOf: identifiers)
    }
}

private func notificationState(
    revision: UInt64,
    percent: Int,
    phase: ConnectionPhase = .connected
) -> ControlState {
    ControlState(
        revision: revision,
        connection: ConnectionState(phase: phase),
        settings: DeviceSettings(
            revision: 1,
            alwaysOn: false,
            fullView: false,
            rotationSeconds: 5,
            brightnessPercent: 80,
            dimAfterSeconds: 60,
            screenOffAfterSeconds: 300,
            alertThresholds: [70, 90],
            soundEnabled: false,
            hiddenProviderIds: [],
            providerOrder: ["claude"]
        ),
        providers: [
            ProviderSummary(
                id: "claude",
                name: "Claude",
                status: "ok",
                windows: [
                    ProviderWindow(
                        kind: "session",
                        label: "Session",
                        usedPercent: percent,
                        resetAtEpoch: 1_785_620_000
                    )
                ]
            )
        ],
        bridge: BridgeStatus(version: "0.1.0", running: true)
    )
}

private func drainNotificationTasks() async {
    for _ in 0 ..< 10 { await Task.yield() }
}


@MainActor
@Test func deniedSystemPermissionSurfacesTheSettingsFixWithoutPrompting() async {
    let delivery = FakeNotificationDelivery()
    delivery.permission = .denied
    let controller = UserNotificationController(
        defaults: UserDefaults(suiteName: "notify-denied-\(UUID().uuidString)")!,
        delivery: delivery
    )

    let enabled = await controller.setEnabled(true)

    #expect(enabled == false)
    #expect(delivery.authorizationRequests == 0)
    #expect(controller.errorMessage == UserNotificationController.deniedMessage)
}

@MainActor
@Test func alreadyAuthorizedPermissionEnablesWithoutReprompting() async {
    let delivery = FakeNotificationDelivery()
    delivery.permission = .authorized
    let controller = UserNotificationController(
        defaults: UserDefaults(suiteName: "notify-authorized-\(UUID().uuidString)")!,
        delivery: delivery
    )

    let enabled = await controller.setEnabled(true)

    #expect(enabled == true)
    #expect(delivery.authorizationRequests == 0)
    #expect(controller.errorMessage == nil)
}
