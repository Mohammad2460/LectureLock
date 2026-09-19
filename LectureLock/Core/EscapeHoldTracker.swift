//
//  EscapeHoldTracker.swift
//  LectureLock
//

import Darwin

/// Emergency release: Escape held continuously for 30 seconds.
///
/// Plain value type with injected timestamps so it can live inside `TapState`
/// (touched from the tap callback without allocating) and be unit-tested.
/// Timestamps come from `EscapeHoldTracker.now()`, a monotonic clock that keeps
/// counting across sleep, so the hold is measured in real elapsed time.
nonisolated struct EscapeHoldTracker: Equatable {
    static let requiredHoldNanos: UInt64 = 30 * 1_000_000_000

    /// Monotonic time of the physical key press, or 0 when Escape is not held.
    private(set) var downAt: UInt64 = 0

    var isHeld: Bool { downAt != 0 }

    @inline(__always)
    static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC) }

    /// Auto-repeat events are ignored. A fresh (non-repeat) key-down always restarts
    /// the hold: it means any earlier key-up was missed, so never give credit for it.
    mutating func keyDown(at now: UInt64, isRepeat: Bool) {
        guard !isRepeat else { return }
        downAt = max(now, 1)
    }

    mutating func keyUp() {
        downAt = 0
    }

    func heldNanos(at now: UInt64) -> UInt64 {
        guard isHeld, now > downAt else { return 0 }
        return now - downAt
    }

    func isComplete(at now: UInt64) -> Bool {
        heldNanos(at: now) >= Self.requiredHoldNanos
    }

    /// 0...1 for the HUD ring.
    func progress(at now: UInt64) -> Double {
        min(1, Double(heldNanos(at: now)) / Double(Self.requiredHoldNanos))
    }
}
