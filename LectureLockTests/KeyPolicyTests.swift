//
//  KeyPolicyTests.swift
//  LectureLockTests
//

import CoreGraphics
import Testing

@testable import LectureLock

private let keyDown = CGEventType.keyDown.rawValue
private let keyUp = CGEventType.keyUp.rawValue

private func decide(
    _ keyCode: Int64,
    flags: CGEventFlags = [],
    type: UInt32 = keyDown,
    whitelist: Whitelist = .jkl
) -> KeyDecision {
    KeyPolicy.decide(eventType: type, keyCode: keyCode, flags: flags, whitelist: whitelist)
}

@Suite("Key policy")
struct KeyPolicyTests {
    @Test("Unmodified j, k, l pass in the default whitelist")
    func jklAllowed() {
        #expect(decide(KeyCode.j) == .allow)
        #expect(decide(KeyCode.k) == .allow)
        #expect(decide(KeyCode.l) == .allow)
        #expect(decide(KeyCode.k, type: keyUp) == .allow)
    }

    @Test("Any command, control, option, shift or fn modifier blocks unconditionally",
          arguments: [
            CGEventFlags.maskCommand,
            .maskControl,
            .maskAlternate,
            .maskShift,
            .maskSecondaryFn,
          ])
    func modifiersBlock(flag: CGEventFlags) {
        #expect(decide(KeyCode.k, flags: flag) == .block)
        #expect(decide(KeyCode.j, flags: [flag, .maskShift]) == .block)
        // Cmd+Tab and friends, whatever the key.
        #expect(decide(48, flags: flag) == .block)
    }

    @Test("Caps lock is a toggle, not a held modifier")
    func capsLockIgnored() {
        #expect(decide(KeyCode.k, flags: .maskAlphaShift) == .allow)
    }

    @Test("Everything outside the whitelist is blocked")
    func othersBlocked() {
        for keyCode in Int64(0)...127 where !KeyPolicy.isWhitelistedForTesting(keyCode, .jkl) && keyCode != KeyCode.escape {
            #expect(decide(keyCode) == .block, "key \(keyCode) should be blocked")
        }
    }

    @Test("Escape is always consumed by the hold tracker, never forwarded")
    func escapeConsumed() {
        #expect(decide(KeyCode.escape) == .escape)
        #expect(decide(KeyCode.escape, type: keyUp) == .escape)
        #expect(decide(KeyCode.escape, flags: .maskCommand) == .escape)
    }

    @Test("Alternate whitelist allows space and arrows, and only those")
    func alternateWhitelist() {
        #expect(decide(KeyCode.space, whitelist: .spaceArrows) == .allow)
        #expect(decide(KeyCode.leftArrow, whitelist: .spaceArrows) == .allow)
        #expect(decide(KeyCode.rightArrow, whitelist: .spaceArrows) == .allow)
        #expect(decide(KeyCode.k, whitelist: .spaceArrows) == .block)
        #expect(decide(KeyCode.space, whitelist: .jkl) == .block)
    }

    @Test("Arrow keys still pass with the fn bit macOS sets implicitly")
    func arrowsCarryFnBit() {
        let arrowFlags: CGEventFlags = [.maskSecondaryFn, .maskNumericPad]
        #expect(decide(KeyCode.leftArrow, flags: arrowFlags, whitelist: .spaceArrows) == .allow)
        #expect(decide(KeyCode.rightArrow, flags: arrowFlags, whitelist: .spaceArrows) == .allow)
        // But a real modifier on top still blocks.
        #expect(decide(KeyCode.leftArrow, flags: [.maskSecondaryFn, .maskCommand], whitelist: .spaceArrows) == .block)
    }

    @Test("Mouse buttons, scroll, modifiers-only and gesture events are blocked",
          arguments: [
            CGEventType.leftMouseDown.rawValue,
            CGEventType.leftMouseUp.rawValue,
            CGEventType.rightMouseDown.rawValue,
            CGEventType.rightMouseUp.rawValue,
            CGEventType.otherMouseDown.rawValue,
            CGEventType.otherMouseUp.rawValue,
            CGEventType.scrollWheel.rawValue,
            CGEventType.flagsChanged.rawValue,
            14, 29, 30, 31, 34,
          ])
    func nonKeyEventsBlocked(type: UInt32) {
        #expect(decide(0, type: type) == .block)
        #expect(decide(KeyCode.k, type: type) == .block)
    }

    @Test("Volume keys pass only when allowed, and only volume keys")
    func volumeKeys() {
        let sub = AuxKey.auxControlSubtype
        for key in [AuxKey.soundUp, AuxKey.soundDown, AuxKey.mute] {
            #expect(KeyPolicy.decideSystemDefined(subtype: sub, auxKeyCode: key, allowVolumeKeys: true) == .allow)
            #expect(KeyPolicy.decideSystemDefined(subtype: sub, auxKeyCode: key, allowVolumeKeys: false) == .block)
        }
        // Brightness (2/3), play/pause (16), next/previous (17/18), backlight (21/22).
        for key in [Int32(2), 3, 16, 17, 18, 21, 22, 160] {
            #expect(KeyPolicy.decideSystemDefined(subtype: sub, auxKeyCode: key, allowVolumeKeys: true) == .block)
        }
        // Other system-defined subtypes are never forwarded.
        #expect(KeyPolicy.decideSystemDefined(subtype: 7, auxKeyCode: AuxKey.soundUp, allowVolumeKeys: true) == .block)
    }

    @Test("The tap mask covers keys, modifiers, all mouse buttons, scroll and gestures")
    func maskContents() {
        for type in [10, 11, 12, 1, 2, 3, 4, 25, 26, 22, 14, 29, 31] {
            #expect(EventTap.eventMask & (CGEventMask(1) << UInt32(type)) != 0, "type \(type) missing")
        }
        // Mouse movement must stay out of the mask so the cursor keeps working.
        for type in [CGEventType.mouseMoved.rawValue, CGEventType.leftMouseDragged.rawValue] {
            #expect(EventTap.eventMask & (CGEventMask(1) << type) == 0)
        }
    }
}

extension KeyPolicy {
    static func isWhitelistedForTesting(_ keyCode: Int64, _ whitelist: Whitelist) -> Bool {
        whitelist.allows(keyCode: keyCode)
    }
}
