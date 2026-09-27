//
//  StatsView.swift
//  LectureLock
//

import SwiftUI

/// Small totals section at the top of the arming panel.
struct StatsView: View {
    let stats: SessionStats

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                figure("Today", stats.todaySeconds)
                figure("This week", stats.weekSeconds)
                figure("All time", stats.allTimeSeconds)
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        var parts = ["\(stats.weekSessions) \(stats.weekSessions == 1 ? "session" : "sessions") this week"]
        if stats.streakDays > 0 { parts.append("\(stats.streakDays)-day streak") }
        if stats.weekEarlyExits > 0 { parts.append("\(stats.weekEarlyExits) ended early") }
        return parts.joined(separator: " · ")
    }

    private func figure(_ label: String, _ seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Self.format(seconds))
                .font(.callout.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `0m`, `45m`, `5h 20m`, `38h`.
    static func format(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let hours = minutes / 60
        if hours == 0 { return "\(minutes)m" }
        if hours >= 10 || minutes % 60 == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes % 60)m"
    }
}
