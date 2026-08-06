import AgentMeterCore
import AgentMeterIPC
import AgentMeterUI
import Foundation
import Testing

@Test func localDaySchedulerUsesTheNextCalendarMidnightAcrossSpringDST() async throws {
    var configuredCalendar = Calendar(identifier: .gregorian)
    configuredCalendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    let calendar = configuredCalendar
    let now = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 29))
    )
    let deadlines = DeadlineRecorder()
    let scheduler = WidgetLocalDayScheduler(
        calendarProvider: { calendar },
        now: { now },
        sleepUntil: { deadline in await deadlines.record(deadline) }
    )

    try await scheduler.waitForNextLocalDay()

    let deadline = try #require(await deadlines.values().only)
    #expect(deadline.timeIntervalSince(now) == 23 * 60 * 60)
    #expect(calendar.dateComponents([.year, .month, .day, .hour], from: deadline)
        == DateComponents(year: 2026, month: 3, day: 30, hour: 0))
}

@Test func localDaySchedulerWakesAndCancelsItsOldDeadlineOnTimeZoneChange() async throws {
    var configuredCalendar = Calendar(identifier: .gregorian)
    configuredCalendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    let calendar = configuredCalendar
    let deadlineSleep = CancellableDeadlineSleep()
    let calendarChange = CalendarChangeGate()
    let scheduler = WidgetLocalDayScheduler(
        calendarProvider: { calendar },
        now: { Date(timeIntervalSince1970: 1_800_000_000) },
        sleepUntil: { deadline in try await deadlineSleep.sleep(until: deadline) },
        waitForCalendarChange: { try await calendarChange.wait() }
    )
    let waiting = Task { try await scheduler.waitForNextLocalDay() }
    await deadlineSleep.waitUntilStarted()

    await calendarChange.open()
    try await waiting.value

    #expect(await deadlineSleep.cancellationCount() == 1)
}

@MainActor
@Test func appModelRefreshesAtLocalDayChangeAndCancelsTheSchedulerOnStop() async {
    let scheduler = ManualLocalDayScheduler()
    let coordinator = DayRecordingSnapshotCoordinator()
    let state = ControlState(
        revision: 4,
        connection: ConnectionState(phase: .connected),
        bridge: BridgeStatus(version: "1", running: true)
    )
    let model = AppModel(
        bridge: FakeBridgeAPI(state: state),
        preferences: AppPreferences(
            defaults: UserDefaults(
                suiteName: "WidgetLocalDaySchedulerTests.\(UUID().uuidString)"
            )!
        ),
        widgetSnapshotCoordinator: coordinator,
        widgetLocalDayScheduler: scheduler
    )
    await model.start()
    await scheduler.waitUntilWaiting()

    await scheduler.fire()
    for _ in 0..<100 where await coordinator.revisions().count < 2 {
        await Task.yield()
    }

    #expect(await coordinator.revisions() == [4, 4])
    await scheduler.waitUntilWaiting()
    await model.stop()
    await scheduler.fire()
    for _ in 0..<10 { await Task.yield() }
    #expect(await coordinator.revisions() == [4, 4])
    #expect(await scheduler.cancellationCount() == 1)
}

@MainActor
@Test func appModelArmsTheDaySchedulerBeforeTheInitialSnapshotRefreshCompletes() async {
    let scheduler = ManualLocalDayScheduler()
    let coordinator = BlockingInitialSnapshotCoordinator()
    let state = ControlState(
        revision: 7,
        connection: ConnectionState(phase: .connected),
        bridge: BridgeStatus(version: "1", running: true)
    )
    let model = AppModel(
        bridge: FakeBridgeAPI(state: state),
        preferences: AppPreferences(
            defaults: UserDefaults(
                suiteName: "WidgetLocalDaySchedulerArmingTests.\(UUID().uuidString)"
            )!
        ),
        widgetSnapshotCoordinator: coordinator,
        widgetLocalDayScheduler: scheduler
    )

    let start = Task { await model.start() }
    await coordinator.waitUntilRefreshEntered()
    for _ in 0..<20 { await Task.yield() }

    #expect(await scheduler.waitCallCount() == 1)
    await coordinator.releaseRefresh()
    await start.value
    await model.stop()
}

private actor DeadlineRecorder {
    private var recorded: [Date] = []

    func record(_ deadline: Date) { recorded.append(deadline) }
    func values() -> [Date] { recorded }
}

private actor CancellableDeadlineSleep {
    private var started = false
    private var startObservers: [CheckedContinuation<Void, Never>] = []
    private var cancellations = 0

    func sleep(until _: Date) async throws {
        started = true
        let observers = startObservers
        startObservers.removeAll()
        observers.forEach { $0.resume() }
        do {
            try await Task.sleep(for: .seconds(3_600))
        } catch {
            cancellations += 1
            throw error
        }
    }

    func waitUntilStarted() async {
        guard started == false else { return }
        await withCheckedContinuation { startObservers.append($0) }
    }

    func cancellationCount() -> Int { cancellations }
}

private actor CalendarChangeGate {
    private var continuation: CheckedContinuation<Void, any Error>?
    private var isOpen = false

    func wait() async throws {
        guard isOpen == false else { return }
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private actor DayRecordingSnapshotCoordinator: WidgetSnapshotCoordinating {
    private var recordedRevisions: [UInt64] = []

    func refresh(state: ControlState) async {
        recordedRevisions.append(state.revision)
    }

    func invalidate(state _: ControlState, invalidation _: WidgetSnapshotInvalidation) async {}

    func revisions() -> [UInt64] { recordedRevisions }
}

private actor BlockingInitialSnapshotCoordinator: WidgetSnapshotCoordinating {
    private var entered = false
    private var released = false
    private var entryObservers: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func refresh(state _: ControlState) async {
        entered = true
        let observers = entryObservers
        entryObservers.removeAll()
        observers.forEach { $0.resume() }
        guard released == false else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func invalidate(state _: ControlState, invalidation _: WidgetSnapshotInvalidation) async {}

    func waitUntilRefreshEntered() async {
        guard entered == false else { return }
        await withCheckedContinuation { entryObservers.append($0) }
    }

    func releaseRefresh() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor ManualLocalDayScheduler: WidgetLocalDayScheduling {
    private enum Cancellation: Error { case cancelled }

    private var waiter: CheckedContinuation<Void, any Error>?
    private var waitingObservers: [CheckedContinuation<Void, Never>] = []
    private var cancellations = 0
    private var waits = 0

    func waitForNextLocalDay() async throws {
        let identifier = UUID()
        waits += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter = continuation
                let observers = waitingObservers
                waitingObservers.removeAll()
                observers.forEach { $0.resume() }
            }
        } onCancel: {
            Task { await self.cancel(identifier: identifier) }
        }
    }

    func waitUntilWaiting() async {
        guard waiter == nil else { return }
        await withCheckedContinuation { waitingObservers.append($0) }
    }

    func fire() {
        let current = waiter
        waiter = nil
        current?.resume()
    }

    func cancellationCount() -> Int { cancellations }
    func waitCallCount() -> Int { waits }

    private func cancel(identifier _: UUID) {
        guard let current = waiter else { return }
        waiter = nil
        cancellations += 1
        current.resume(throwing: Cancellation.cancelled)
    }
}

private extension Collection {
    var only: Element? { count == 1 ? first : nil }
}
