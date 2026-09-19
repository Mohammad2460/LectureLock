//
//  TapSharedState.swift
//  LectureLock
//

import CoreGraphics
import os

/// All state shared between the event-tap callback, the watchdog queue and the
/// main thread. Plain old data only: no references, no allocation on access.
nonisolated struct TapState {
    static let maxTimeoutReenables = 3

    var whitelist: Whitelist
    /// Volume up / down / mute keys stay usable.
    var allowVolumeKeys: Bool
    /// Dry run: every event is evaluated but forwarded unchanged.
    var passThrough: Bool
    var escape = EscapeHoldTracker()
    var timeoutReenables = 0
    /// Count of `tapDisabledByUserInput` notices caused by our own
    /// `tapEnable(false)` calls, which must not be read as macOS killing the tap.
    var expectedDisableNotices = 0
    /// Set from the callback when it wants the session to end; acted on by the watchdog poll.
    var pendingRelease: ReleaseReason?
    /// Once true the callback forwards everything and the release is owned by whoever set it.
    var isReleased = false

    /// Called when macOS disables the tap for being slow. Returns true if it may be re-enabled.
    mutating func registerTimeout() -> Bool {
        guard !isReleased else { return false }
        if timeoutReenables < Self.maxTimeoutReenables {
            timeoutReenables += 1
            return true
        }
        requestRelease(.tapTimeout)
        return false
    }

    mutating func requestRelease(_ reason: ReleaseReason) {
        if pendingRelease == nil { pendingRelease = reason }
    }

    /// macOS sends `tapDisabledByUserInput` both when it disables the tap itself and
    /// when *we* disable it. Returns whether the tap should be re-enabled (our own
    /// notice, session still live) or the session ended.
    mutating func handleUserInputDisable() -> Bool {
        guard !isReleased else { return false }
        if expectedDisableNotices > 0 {
            expectedDisableNotices -= 1
            return true
        }
        requestRelease(.tapDisabledByUserInput)
        return false
    }
}

/// Owns the `TapState` memory and the unfair lock guarding it. A pointer to this
/// object is the tap's `userInfo`; it must outlive the tap (LockController keeps
/// it until the tap is invalidated).
nonisolated final class TapContext: @unchecked Sendable {
    private let lock: UnsafeMutablePointer<os_unfair_lock_s>
    private let state: UnsafeMutablePointer<TapState>

    /// Written once on the main thread before the tap is enabled or the watchdog
    /// started; read-only afterwards.
    nonisolated(unsafe) var machPort: CFMachPort?

    init(whitelist: Whitelist, allowVolumeKeys: Bool, passThrough: Bool) {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock_s())
        state = .allocate(capacity: 1)
        state.initialize(to: TapState(
            whitelist: whitelist,
            allowVolumeKeys: allowVolumeKeys,
            passThrough: passThrough
        ))
    }

    deinit {
        state.deinitialize(count: 1)
        state.deallocate()
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    @inline(__always)
    func withState<R>(_ body: (inout TapState) -> R) -> R {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return body(&state.pointee)
    }

    /// Marks the session released. Returns true only for the first caller, which
    /// then owns running the release.
    func claimRelease() -> Bool {
        withState { state in
            guard !state.isReleased else { return false }
            state.isReleased = true
            return true
        }
    }

    func setTapEnabled(_ enabled: Bool) {
        guard let machPort else { return }
        if !enabled {
            // Our own disable produces a notice the callback must ignore.
            withState { $0.expectedDisableNotices += 1 }
        }
        CGEvent.tapEnable(tap: machPort, enable: enabled)
    }

    var isTapEnabled: Bool {
        guard let machPort else { return false }
        return CGEvent.tapIsEnabled(tap: machPort)
    }
}
