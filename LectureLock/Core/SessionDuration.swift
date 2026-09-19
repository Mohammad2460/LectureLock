//
//  SessionDuration.swift
//  LectureLock
//

import Foundation

/// A lock duration. The 90-minute hard cap is enforced here, in the model, so
/// no caller (UI, settings, tests) can construct a longer session.
nonisolated struct SessionDuration: Equatable, Sendable {
    static let minimumMinutes = 1
    static let maximumMinutes = 90
    static let maximumSeconds = maximumMinutes * 60
    static let presetMinutes = [25, 45, 60, 90]

    /// Always within 1 ... 5400.
    let seconds: Int

    /// Clamps to 1–90 minutes.
    init(minutes: Int) {
        let clamped = min(max(minutes, Self.minimumMinutes), Self.maximumMinutes)
        seconds = clamped * 60
    }

    /// Second-granular duration for short test sessions. Still clamped to the hard cap.
    init(seconds: Int) {
        self.seconds = min(max(seconds, 1), Self.maximumSeconds)
    }

    var timeInterval: TimeInterval { TimeInterval(seconds) }
    var wholeMinutes: Int { seconds / 60 }
}
