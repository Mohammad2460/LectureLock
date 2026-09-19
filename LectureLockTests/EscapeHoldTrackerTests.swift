//
//  EscapeHoldTrackerTests.swift
//  LectureLockTests
//

import Testing

@testable import LectureLock

private let second: UInt64 = 1_000_000_000

@Suite("Escape hold tracker")
struct EscapeHoldTrackerTests {
    @Test("Thirty seconds of continuous hold completes; 29.9 does not")
    func completesAtThirtySeconds() {
        var tracker = EscapeHoldTracker()
        tracker.keyDown(at: 1_000 * second, isRepeat: false)
        #expect(!tracker.isComplete(at: 1_000 * second + 29 * second + 900_000_000))
        #expect(tracker.isComplete(at: 1_030 * second))
    }

    @Test("Early release resets the hold to zero")
    func releaseResets() {
        var tracker = EscapeHoldTracker()
        tracker.keyDown(at: 0, isRepeat: false)
        tracker.keyUp()
        #expect(!tracker.isHeld)
        #expect(tracker.heldNanos(at: 60 * second) == 0)
        #expect(!tracker.isComplete(at: 60 * second))
    }

    @Test("Key repeats are ignored and never start or extend a hold")
    func repeatsIgnored() {
        var tracker = EscapeHoldTracker()
        tracker.keyDown(at: 5 * second, isRepeat: true)
        #expect(!tracker.isHeld)

        tracker.keyDown(at: 10 * second, isRepeat: false)
        tracker.keyDown(at: 11 * second, isRepeat: true)
        #expect(tracker.downAt == 10 * second)
        #expect(tracker.heldNanos(at: 12 * second) == 2 * second)
    }

    @Test("A fresh press restarts timing, so a missed key-up cannot release early")
    func freshPressRestarts() {
        var tracker = EscapeHoldTracker()
        tracker.keyDown(at: 0, isRepeat: false)
        tracker.keyDown(at: 25 * second, isRepeat: false) // key-up was lost
        #expect(!tracker.isComplete(at: 30 * second))
        #expect(tracker.isComplete(at: 55 * second))
    }

    @Test("Progress is clamped to 0...1")
    func progressClamped() {
        var tracker = EscapeHoldTracker()
        #expect(tracker.progress(at: 0) == 0)
        tracker.keyDown(at: 0, isRepeat: false)
        #expect(abs(tracker.progress(at: 15 * second) - 0.5) < 0.0001)
        #expect(tracker.progress(at: 300 * second) == 1)
    }
}
