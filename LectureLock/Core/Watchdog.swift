//
//  Watchdog.swift
//  LectureLock
//

import CoreGraphics
import Dispatch
import Foundation

/// Ends the lock independently of the main thread.
///
/// Runs on its own serial queue. A wall-clock `DispatchSourceTimer` fires at the
/// deadline (computed once, at arm time); a 100 ms poll also checks the deadline,
/// the Escape hold, and release requests from the tap callback. Whichever wins
/// disables the tap *directly* from this queue, then asks the main thread to run
/// the normal release path. So even with a hung main thread, input comes back.
nonisolated final class Watchdog: @unchecked Sendable {
    private static let escapeKeyCode: CGKeyCode = 53

    private let queue = DispatchQueue(label: "com.mohammad.lecturelock.watchdog", qos: .userInteractive)
    private let context: TapContext
    private let deadline: Date
    private let onRelease: @Sendable (ReleaseReason) -> Void

    // Created in start(), cancelled in cancel(); both called on the main thread.
    private var deadlineTimer: DispatchSourceTimer?
    private var pollTimer: DispatchSourceTimer?

    init(context: TapContext, deadline: Date, onRelease: @escaping @Sendable (ReleaseReason) -> Void) {
        self.context = context
        self.deadline = deadline
        self.onRelease = onRelease
    }

    func start() {
        let deadlineTimer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        deadlineTimer.schedule(wallDeadline: Self.wallTime(for: deadline), leeway: .milliseconds(20))
        deadlineTimer.setEventHandler { [self] in fire(.deadline) }

        let pollTimer = DispatchSource.makeTimerSource(queue: queue)
        pollTimer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100), leeway: .milliseconds(20))
        pollTimer.setEventHandler { [self] in poll() }

        self.deadlineTimer = deadlineTimer
        self.pollTimer = pollTimer
        deadlineTimer.resume()
        pollTimer.resume()
    }

    func cancel() {
        deadlineTimer?.cancel()
        pollTimer?.cancel()
        deadlineTimer = nil
        pollTimer = nil
    }

    private func poll() {
        if Date() >= deadline {
            fire(.deadline)
            return
        }
        let now = EscapeHoldTracker.now()
        // Guard against a missed key-up: if Escape isn't physically down, the hold is over.
        let escapePhysicallyDown = CGEventSource.keyState(.hidSystemState, key: Self.escapeKeyCode)
        let reason: ReleaseReason? = context.withState { state in
            guard !state.isReleased else { return nil }
            if state.escape.isHeld && !escapePhysicallyDown { state.escape.keyUp() }
            if state.escape.isComplete(at: now) { return .escapeHold }
            return state.pendingRelease
        }
        if let reason { fire(reason) }
    }

    private func fire(_ reason: ReleaseReason) {
        guard context.claimRelease() else { return }
        context.setTapEnabled(false)
        onRelease(reason)
    }

    private static func wallTime(for date: Date) -> DispatchWallTime {
        let interval = date.timeIntervalSince1970
        let seconds = interval.rounded(.down)
        let spec = timespec(tv_sec: Int(seconds), tv_nsec: Int((interval - seconds) * 1_000_000_000))
        return DispatchWallTime(timespec: spec)
    }
}
