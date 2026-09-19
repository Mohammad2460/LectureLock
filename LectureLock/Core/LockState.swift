//
//  LockState.swift
//  LectureLock
//

/// Lifecycle of a lock session. Transitions happen only on the main thread, in `LockController`.
enum LockState: Equatable {
    case idle
    case arming
    case locked
    case releasing
    case terminating
}

/// Why a session ended. The raw value is what gets written to the session log.
nonisolated enum ReleaseReason: String, Codable, Sendable {
    /// Planned duration elapsed (watchdog fired).
    case deadline
    /// Escape was held continuously for 30 seconds.
    case escapeHold
    /// Deadline had already passed when the Mac woke from sleep.
    case wakeAfterDeadline
    /// macOS disabled the tap for being slow more than the re-enable budget allows.
    case tapTimeout
    /// macOS disabled the tap because of user input (e.g. secure event input policies).
    case tapDisabledByUserInput
    /// App quit normally.
    case appQuit
    /// Process received SIGTERM / SIGINT.
    case signal
    /// Dry run ended from the menu-bar panel.
    case endedFromMenu
}
