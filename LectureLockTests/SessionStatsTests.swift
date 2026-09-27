//
//  SessionStatsTests.swift
//  LectureLockTests
//

import Foundation
import Testing

@testable import LectureLock

@Suite("Session stats")
struct SessionStatsTests {
    /// Fixed Gregorian calendar, UTC, weeks start Monday, so results never
    /// depend on the machine running the tests.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Wednesday 2026-09-23 18:00 UTC.
    private static let now = date(2026, 9, 23, 18)

    private static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private static func record(
        _ start: Date,
        minutes: Int,
        reason: ReleaseReason = .deadline,
        dryRun: Bool = false
    ) -> SessionRecord {
        SessionRecord(
            start: start,
            plannedSeconds: minutes * 60,
            actualSeconds: minutes * 60,
            releaseMethod: reason,
            whitelist: 0,
            dryRun: dryRun
        )
    }

    private func compute(_ records: [SessionRecord]) -> SessionStats {
        SessionStats.compute(records: records, now: Self.now, calendar: Self.calendar)
    }

    @Test("No records gives empty stats")
    func empty() {
        let stats = compute([])
        #expect(stats == SessionStats())
        #expect(!stats.hasSessions)
    }

    @Test("Dry runs are excluded from every figure")
    func dryRunExcluded() {
        let stats = compute([Self.record(Self.date(2026, 9, 23), minutes: 45, dryRun: true)])
        #expect(stats == SessionStats())
    }

    @Test("Today, this week and all-time totals split on calendar boundaries")
    func totals() {
        let stats = compute([
            Self.record(Self.date(2026, 9, 23), minutes: 45), // today
            Self.record(Self.date(2026, 9, 21), minutes: 30), // Monday, this week
            Self.record(Self.date(2026, 9, 20), minutes: 60), // Sunday, last week
            Self.record(Self.date(2025, 1, 1), minutes: 10),
        ])
        #expect(stats.todaySeconds == 45 * 60)
        #expect(stats.weekSeconds == 75 * 60)
        #expect(stats.allTimeSeconds == 145 * 60)
        #expect(stats.weekSessions == 2)
        #expect(stats.hasSessions)
    }

    @Test("Only escape holds this week count as early exits")
    func earlyExits() {
        let stats = compute([
            Self.record(Self.date(2026, 9, 23), minutes: 5, reason: .escapeHold),
            Self.record(Self.date(2026, 9, 22), minutes: 5, reason: .tapTimeout),
            Self.record(Self.date(2026, 9, 15), minutes: 5, reason: .escapeHold),
        ])
        #expect(stats.weekEarlyExits == 1)
    }

    @Test("Streak counts consecutive days ending today and stops at a gap")
    func streakWithGap() {
        let stats = compute([
            Self.record(Self.date(2026, 9, 23), minutes: 10),
            Self.record(Self.date(2026, 9, 22), minutes: 10),
            Self.record(Self.date(2026, 9, 21), minutes: 10),
            Self.record(Self.date(2026, 9, 19), minutes: 10),
        ])
        #expect(stats.streakDays == 3)
    }

    @Test("A streak is still alive if the last session was yesterday")
    func streakFromYesterday() {
        let stats = compute([
            Self.record(Self.date(2026, 9, 22), minutes: 10),
            Self.record(Self.date(2026, 9, 21), minutes: 10),
        ])
        #expect(stats.streakDays == 2)
    }

    @Test("A streak is broken when the last session was two days ago")
    func streakBroken() {
        let stats = compute([Self.record(Self.date(2026, 9, 21), minutes: 10)])
        #expect(stats.streakDays == 0)
    }

    @Test("Sessions under a minute do not count towards the streak")
    func shortSessionsSkipStreak() {
        var short = Self.record(Self.date(2026, 9, 23), minutes: 0)
        short.actualSeconds = 59
        let stats = compute([short])
        #expect(stats.streakDays == 0)
        #expect(stats.todaySeconds == 59)
    }

    @Test("Corrupt log lines are skipped, valid ones kept")
    func parseSkipsCorruptLines() throws {
        let good = """
        {"actualSeconds":60,"dryRun":false,"plannedSeconds":60,"releaseMethod":"deadline","start":"2026-09-23T10:00:00Z","whitelist":0}
        """
        let data = Data((good + "\nnot json\n\n{\"half\":\n" + good + "\n").utf8)
        let records = SessionLog.parse(data)
        #expect(records.count == 2)
        #expect(records.first?.actualSeconds == 60)
    }
}
