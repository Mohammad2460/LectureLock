//
//  KeyPolicy.swift
//  LectureLock
//

import CoreGraphics

nonisolated enum KeyDecision: Equatable {
    /// Forward to the frontmost app.
    case allow
    /// Swallow.
    case block
    /// Escape: consumed by the hold tracker and never forwarded.
    case escape
}

/// Which keys stay usable during a lock.
nonisolated enum Whitelist: Int, CaseIterable, Identifiable, Sendable {
    /// YouTube-style: j back 10s, k play/pause, l forward 10s.
    case jkl = 0
    /// Space play/pause, ← / → seek.
    case spaceArrows = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .jkl: "J  K  L"
        case .spaceArrows: "Space  ←  →"
        }
    }

    var allowedKeyCodes: [Int64] {
        switch self {
        case .jkl: [KeyCode.j, KeyCode.k, KeyCode.l]
        case .spaceArrows: [KeyCode.space, KeyCode.leftArrow, KeyCode.rightArrow]
        }
    }

    @inline(__always)
    func allows(keyCode: Int64) -> Bool {
        switch self {
        case .jkl: keyCode == KeyCode.j || keyCode == KeyCode.k || keyCode == KeyCode.l
        case .spaceArrows: keyCode == KeyCode.space || keyCode == KeyCode.leftArrow || keyCode == KeyCode.rightArrow
        }
    }
}

nonisolated enum KeyCode {
    static let j: Int64 = 38
    static let k: Int64 = 40
    static let l: Int64 = 37
    static let space: Int64 = 49
    static let escape: Int64 = 53
    static let leftArrow: Int64 = 123
    static let rightArrow: Int64 = 124

    @inline(__always)
    static func isArrow(_ keyCode: Int64) -> Bool {
        keyCode == leftArrow || keyCode == rightArrow
    }
}

/// Aux-control (media) key codes carried in a system-defined event's `data1`.
nonisolated enum AuxKey {
    static let soundUp: Int32 = 0
    static let soundDown: Int32 = 1
    static let mute: Int32 = 7
    /// `NX_SUBTYPE_AUX_CONTROL_BUTTONS`
    static let auxControlSubtype: Int16 = 8
}

/// The whole input policy, as one pure function. Whitelist only — anything not
/// explicitly allowed is blocked.
///
/// Called from the event-tap callback on every system-wide input event, so it
/// allocates nothing and touches no shared state.
nonisolated enum KeyPolicy {
    /// Modifiers that make a key press "modified". Shift counts: the whitelist is
    /// unmodified keys only. Caps lock (`maskAlphaShift`) is a toggle, not a held
    /// modifier, so it is ignored.
    static let blockingModifiers: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn,
    ]

    /// - Parameter eventType: raw `CGEventType` value, so event types without a
    ///   Swift case (gestures, system-defined) can be handled too.
    @inline(__always)
    static func decide(
        eventType: UInt32,
        keyCode: Int64,
        flags: CGEventFlags,
        whitelist: Whitelist
    ) -> KeyDecision {
        switch eventType {
        case CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue:
            // Escape first: it is never forwarded, whatever modifiers are down, and
            // the tracker must see its key-up to reset the hold.
            if keyCode == KeyCode.escape { return .escape }

            var active = flags.intersection(blockingModifiers)
            // Arrow keys always carry the fn bit on Apple keyboards; that is not a
            // modifier the user pressed.
            if KeyCode.isArrow(keyCode) { active.remove(.maskSecondaryFn) }
            if !active.isEmpty { return .block }

            return whitelist.allows(keyCode: keyCode) ? .allow : .block

        default:
            // flagsChanged, every mouse button, scroll wheel, trackpad gestures,
            // system-defined (media/brightness) keys: all blocked.
            // Plain cursor movement is never in the tap's event mask, so it stays free.
            return .block
        }
    }

    /// Volume keys, when the setting allows them. Every other media key
    /// (brightness, play/pause, Mission Control, keyboard backlight) stays blocked:
    /// still a whitelist, just a second, narrower one.
    @inline(__always)
    static func decideSystemDefined(
        subtype: Int16,
        auxKeyCode: Int32,
        allowVolumeKeys: Bool
    ) -> KeyDecision {
        guard allowVolumeKeys, subtype == AuxKey.auxControlSubtype else { return .block }
        switch auxKeyCode {
        case AuxKey.soundUp, AuxKey.soundDown, AuxKey.mute: return .allow
        default: return .block
        }
    }
}
