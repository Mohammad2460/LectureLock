//
//  EventTap.swift
//  LectureLock
//

import AppKit
import CoreGraphics
import Foundation

/// The tap callback. Runs on the main run loop for every system-wide input event.
///
/// Discipline: no allocation, no logging, no UI, no Swift concurrency, no work
/// beyond reading the event and touching `TapState` under one unfair lock.
private func lectureLockTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<TapContext>.fromOpaque(userInfo).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout:
        // macOS decided the tap was too slow. Re-enable a bounded number of times,
        // then end the session (the watchdog poll picks up the request).
        if context.withState({ $0.registerTimeout() }) {
            context.setTapEnabled(true)
        }
        return Unmanaged.passUnretained(event)

    case .tapDisabledByUserInput:
        if context.withState({ $0.handleUserInputDisable() }) {
            context.setTapEnabled(true)
        }
        return Unmanaged.passUnretained(event)

    default:
        break
    }

    // System-defined events carry the pressed media key in `data1`, which only
    // NSEvent exposes. This is the one place the callback touches AppKit: it runs
    // solely for media-key events (a handful per session), never on the keyboard or
    // mouse path, and only when volume keys are allowed at all.
    if type.rawValue == 14 {
        let forward = context.withState { state -> Bool in
            if state.isReleased { return true }
            guard state.allowVolumeKeys else { return state.passThrough }
            guard let nsEvent = NSEvent(cgEvent: event) else { return state.passThrough }
            let decision = KeyPolicy.decideSystemDefined(
                subtype: nsEvent.subtype.rawValue,
                auxKeyCode: Int32((nsEvent.data1 & 0xFFFF_0000) >> 16),
                allowVolumeKeys: true
            )
            return state.passThrough || decision == .allow
        }
        return forward ? Unmanaged.passUnretained(event) : nil
    }

    let isKeyEvent = (type == .keyDown || type == .keyUp)
    let keyCode = isKeyEvent ? event.getIntegerValueField(.keyboardEventKeycode) : 0
    let isEscape = isKeyEvent && keyCode == KeyCode.escape
    let isRepeat = isEscape && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let now = isEscape ? EscapeHoldTracker.now() : 0

    let forward = context.withState { state -> Bool in
        if state.isReleased { return true }

        let decision = KeyPolicy.decide(
            eventType: type.rawValue,
            keyCode: keyCode,
            flags: event.flags,
            whitelist: state.whitelist
        )

        if decision == .escape {
            if type == .keyDown {
                state.escape.keyDown(at: now, isRepeat: isRepeat)
            } else {
                state.escape.keyUp()
            }
        }

        return state.passThrough || decision == .allow
    }

    return forward ? Unmanaged.passUnretained(event) : nil
}

/// One HID-level event tap.
///
/// `.cghidEventTap` is required: the session tap sits after the WindowServer has
/// already handled things like Cmd+Tab, so it would let them through.
final class EventTap {
    private let context: TapContext
    private let machPort: CFMachPort
    private let runLoopSource: CFRunLoopSource
    private var isInvalidated = false

    /// Keyboard, modifiers, every mouse button, scroll wheel, trackpad gestures and
    /// system-defined (media key) events. Mouse *movement* is deliberately absent so
    /// the cursor keeps working.
    static let eventMask: CGEventMask = {
        let types: [UInt32] = [
            CGEventType.keyDown.rawValue,
            CGEventType.keyUp.rawValue,
            CGEventType.flagsChanged.rawValue,
            CGEventType.leftMouseDown.rawValue,
            CGEventType.leftMouseUp.rawValue,
            CGEventType.rightMouseDown.rawValue,
            CGEventType.rightMouseUp.rawValue,
            CGEventType.otherMouseDown.rawValue,
            CGEventType.otherMouseUp.rawValue,
            CGEventType.scrollWheel.rawValue,
            14, // NSEvent.EventType.systemDefined (media / brightness keys)
            18, // rotate
            19, // beginGesture
            20, // endGesture
            29, // gesture (includes Mission Control / space-switching swipes)
            30, // magnify
            31, // swipe
            32, // smartMagnify
            34, // pressure (force click)
        ]
        return types.reduce(into: CGEventMask(0)) { $0 |= CGEventMask(1) << $1 }
    }()

    /// Returns nil when Accessibility permission is missing.
    init?(context: TapContext) {
        guard let machPort = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: lectureLockTapCallback,
            userInfo: Unmanaged.passUnretained(context).toOpaque()
        ) else { return nil }

        // tapCreate returns an enabled tap; keep it off until the caller is ready
        // (the watchdog must be armed before anything can block input).
        context.machPort = machPort
        context.setTapEnabled(false)

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, machPort, 0) else {
            CFMachPortInvalidate(machPort)
            return nil
        }

        self.context = context
        self.machPort = machPort
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    var isEnabled: Bool {
        !isInvalidated && CGEvent.tapIsEnabled(tap: machPort)
    }

    func enable() {
        guard !isInvalidated else { return }
        CGEvent.tapEnable(tap: machPort, enable: true)
    }

    /// Disables and tears down the tap. Safe to call more than once.
    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        context.setTapEnabled(false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CFMachPortInvalidate(machPort)
    }
}
