import AgentMeterCore
import Foundation
import Testing

@Test func fixedHistoryRangesAlignToCompleteLocalBuckets() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 2 * 3_600))
    let now = try #require(
        calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 3,
            hour: 15,
            minute: 47
        ))
    )

    let day = UsageHistoryRange.last24Hours.query(now: now, calendar: calendar)
    let week = UsageHistoryRange.last7Days.query(now: now, calendar: calendar)
    let month = UsageHistoryRange.last30Days.query(now: now, calendar: calendar)

    #expect(day.bucketSeconds == 3_600)
    #expect(day.currentCycle == false)
    #expect(day.sinceEpoch == Int(now.timeIntervalSince1970) - (23 * 3_600 + 47 * 60))
    #expect(week.bucketSeconds == 86_400)
    #expect(calendar.dateComponents(
        [.day],
        from: Date(timeIntervalSince1970: Double(week.sinceEpoch)),
        to: calendar.startOfDay(for: now)
    ).day == 6)
    #expect(month.bucketSeconds == 86_400)
    #expect(calendar.dateComponents(
        [.day],
        from: Date(timeIntervalSince1970: Double(month.sinceEpoch)),
        to: calendar.startOfDay(for: now)
    ).day == 29)
}

@Test func cycleHistoryRequestsTheObservedCurrentCycle() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let query = UsageHistoryRange.currentCycle.query(now: now)

    #expect(query.currentCycle)
    #expect(query.bucketSeconds == nil)
    #expect(query.sinceEpoch == 1_800_000_000 - 30 * 86_400)
}
