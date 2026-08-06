import Foundation

public protocol WidgetLocalDayScheduling: Sendable {
    func waitForNextLocalDay() async throws
}

public enum WidgetLocalDaySchedulerError: Error {
    case nextDayUnavailable
}

public struct WidgetLocalDayScheduler: WidgetLocalDayScheduling {
    private let calendarProvider: @Sendable () -> Calendar
    private let now: @Sendable () -> Date
    private let sleepUntil: @Sendable (Date) async throws -> Void
    private let waitForCalendarChange: @Sendable () async throws -> Void

    public init(
        calendarProvider: @escaping @Sendable () -> Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            return calendar
        },
        now: @escaping @Sendable () -> Date = { .now },
        sleepUntil: @escaping @Sendable (Date) async throws -> Void = { deadline in
            let seconds = max(0, deadline.timeIntervalSinceNow)
            try await Task.sleep(for: .seconds(seconds))
        },
        waitForCalendarChange: @escaping @Sendable () async throws -> Void = {
            for await _ in NotificationCenter.default.notifications(
                named: .NSSystemTimeZoneDidChange
            ) {
                try Task.checkCancellation()
                return
            }
            throw CancellationError()
        }
    ) {
        self.calendarProvider = calendarProvider
        self.now = now
        self.sleepUntil = sleepUntil
        self.waitForCalendarChange = waitForCalendarChange
    }

    public func waitForNextLocalDay() async throws {
        let calendar = currentGregorianCalendar()
        let reference = now()
        let start = calendar.startOfDay(for: reference)
        guard let deadline = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw WidgetLocalDaySchedulerError.nextDayUnavailable
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await sleepUntil(deadline) }
            group.addTask { try await waitForCalendarChange() }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func currentGregorianCalendar() -> Calendar {
        let configured = calendarProvider()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = configured.timeZone
        return calendar
    }
}
