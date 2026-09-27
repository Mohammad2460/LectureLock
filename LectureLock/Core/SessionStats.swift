//
//  SessionStats.swift
//  LectureLock
//

import Foundation

/// Totals shown in the arming panel, derived from the session log.
/// Dry runs never count.
nonisolated struct SessionStats: Equatable, Sendable {
    var todaySeconds = 0
    var weekSeconds = 0
    var allTimeSeconds = 0
    var allTimeSessions = 0
    var weekSessions = 0
    /// Sessions this week ended by holding Escape.
    var weekEarlyExits = 0
    /// Consecutive days, ending today (or yesterday), with a session of at least a minute.
    var streakDays = 0

    var hasSessions: Bool { allTimeSessions > 0 }

    /// Shortest session that keeps a streak alive.
    static let streakMinimumSeconds = 60

    /// Pure: same records, time and calendar always give the same stats.
    /// A session belongs to the day and week it started in.
    static func compute(records: [SessionRecord], now: Date, calendar: Calendar) -> SessionStats {
        var stats = SessionStats()
        let today = calendar.startOfDay(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        var streakDaySet = Set<Date>()

        for record in records where !record.dryRun {
            let seconds = max(0, record.actualSeconds)
            stats.allTimeSeconds += seconds
            stats.allTimeSessions += 1

            let day = calendar.startOfDay(for: record.start)
            if day == today { stats.todaySeconds += seconds }
            if let week, week.contains(record.start) {
                stats.weekSeconds += seconds
                stats.weekSessions += 1
                if record.releaseMethod == .escapeHold { stats.weekEarlyExits += 1 }
            }
            if seconds >= streakMinimumSeconds { streakDaySet.insert(day) }
        }

        // Today without a session yet doesn't break the streak; start from yesterday.
        var day = today
        if !streakDaySet.contains(day), let yesterday = calendar.date(byAdding: .day, value: -1, to: day) {
            day = yesterday
        }
        while streakDaySet.contains(day) {
            stats.streakDays += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return stats
    }
}
