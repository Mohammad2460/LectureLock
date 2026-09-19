# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

LectureLock: macOS 13+ menu-bar app (LSUIElement, no Dock icon). For a chosen duration it installs one CGEventTap that blocks all keyboard/mouse input system-wide except a small whitelist of video-control keys, so the user can't switch away from a lecture in the browser. It never touches the browser or video — input filtering only.

All seven milestones are implemented (menu-bar skeleton, Accessibility checks, Escape-hold
tracker + release path, blocking tap + tested key policy, HUD, arming panel, sleep/wake +
secure input + session log + SIGTERM). The original plan's "listen-only tap" stage became a
permanent **dry-run** mode instead: a `.defaultTap` that evaluates every event and forwards
it (`TapState.passThrough`). It needs only Accessibility permission, unlike a listen-only
keyboard tap which would demand Input Monitoring.

Unverified by automated tests, because it cannot be tested without locking the machine:
actual blocking behaviour, the HUD's on-screen placement, and the arming panel's focus
behaviour. Use dry run for those.

## Commands

```sh
# Build (Debug)
xcodebuild -project LectureLock.xcodeproj -scheme LectureLock -configuration Debug build

# Tests (Swift Testing; hosted in the app bundle)
xcodebuild test -project LectureLock.xcodeproj -scheme LectureLock -destination 'platform=macOS,arch=arm64'
# One suite / one test
xcodebuild test -project LectureLock.xcodeproj -scheme LectureLock -destination 'platform=macOS,arch=arm64' \
  -only-testing:LectureLockTests/KeyPolicyTests
xcodebuild test -project LectureLock.xcodeproj -scheme LectureLock -destination 'platform=macOS,arch=arm64' \
  -only-testing:LectureLockTests/KeyPolicyTests/escapeConsumed

# Inspect signature (hardened runtime shows as flags=...runtime)
codesign -dv --verbose=4 path/to/LectureLock.app
```

Project uses Xcode 16+ file-system-synchronized groups: any `.swift` file placed under `LectureLock/` (app) or `LectureLockTests/` (tests) joins its target automatically — no `project.pbxproj` edits needed for new sources. The scheme is shared (`xcshareddata/xcschemes/LectureLock.xcscheme`) and includes the test action.

## Build settings that must stay as they are

- `ENABLE_APP_SANDBOX = NO` — event taps don't work sandboxed.
- `ENABLE_HARDENED_RUNTIME = YES`, `MACOSX_DEPLOYMENT_TARGET = 13.0`, `INFOPLIST_KEY_LSUIElement = YES` (Info.plist is generated; no plist file).
- Bundle id `com.mohammad.lecturelock`.
- Debug should be signed with a self-signed "LectureLock Dev" cert (see README) — ad-hoc signatures make macOS drop the Accessibility grant on every rebuild.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: every type is MainActor unless marked otherwise. Tap callback, key policy, watchdog, and shared tap state must be explicitly `nonisolated`.

## Non-negotiable safety rules

These override any feature work. Implement before anything that blocks input.

1. **Watchdog**: `DispatchSourceTimer` on a dedicated queue disables the tap at the deadline regardless of app/main-thread state. Deadline computed once from `Date()` at arm time; never accumulate ticks.
2. **Emergency release**: hold Escape 30 s continuously, measured by wall clock keyDown→keyUp, ignoring autorepeat events; resets on early release. Escape is never forwarded.
3. **90-minute hard cap enforced in the model layer**, not only in UI.
4. **Never** use `NSApplication.PresentationOptions.disableForceQuit` or `.disableSessionTermination`. If the process dies or hangs, input must return to normal — do not defend against that.
5. On `NSWorkspace.didWakeNotification`, re-check deadline and release if passed.

## Architecture (target design)

- **One tap, no overlay window**: `CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap, …)`. Must be HID tap — the session tap sits after WindowServer handles Cmd+Tab. Blocking both keyboard and mouse keeps the browser focused.
- Event mask: keyDown, keyUp, flagsChanged, all mouse down/up, scrollWheel. `tapDisabledByTimeout` → re-enable, max 3 per session, then release. `tapDisabledByUserInput` → release cleanly.
- **Key policy** is a pure, unit-tested function. Whitelist only, never a denylist:
  - any cmd/ctrl/option/fn modifier → block
  - unmodified k(40), j(38), l(37) → allow; alternate whitelist setting: Space(49), ←(123), →(124)
  - Escape(53) → hold tracker, never forwarded
  - mouse buttons + scroll → block (cursor movement free)
  - system-defined (type 14) → `decideSystemDefined`: volume up/down/mute allowed when the
    `allowVolumeKeys` setting is on, every other media key blocked
  - everything else → block
- **Tap callback discipline**: runs on every system-wide input event. No allocation, logging, locks other than one `os_unfair_lock`, UI, or Swift concurrency. One documented exception: system-defined (type 14) events construct an `NSEvent` to read `data1`, the only way to get the media-key code. That path runs a handful of times per session and never on the keyboard/mouse path. Share state with main thread through one POD struct behind a pointer (passed as `userInfo`). Must stay under 1 ms.
- **State machine**: `idle → arming → locked → releasing → idle`, plus `terminating`. All transitions on main thread in a single `LockController`. **Release is one code path for every cause**: disable tap → cancel timers → hide HUD → write session log.
- **Menu-bar UI** is `NSStatusItem` + a non-activating `NSPanel` for the arming window (not SwiftUI `MenuBarExtra`), so the browser stays frontmost — arming requires a browser to be frontmost, re-verified 400 ms after pressing Arm. Never synthesize clicks.
- **HUD** is off by default (`showHUD` setting) and shown only during an Escape hold, so the
  hold always has feedback. When on: borderless non-activating `NSPanel`, `.statusBar` level, `ignoresMouseEvents = true`, `.canJoinAllSpaces` + `.fullScreenAuxiliary`, top-right 20 pt inset. Shows remaining time + "hold esc to exit"; ring + countdown during Escape hold. No other animation.
- **Session log**: one JSON line per session at `~/Library/Application Support/LectureLock/sessions.jsonl` (start, planned duration, actual duration, release method). Local only.

Beyond the original spec, the tap mask also blocks trackpad gesture events (raw types 18–20,
29–32, 34) and system-defined events (14, media/brightness keys), because Mission Control
swipes and media keys would otherwise be a hole in "cannot switch away". Whitelist-only still
holds: `KeyPolicy.decide` returns `.block` for every non-key event type.

Distribution is source-only: `scripts/install.sh` builds Release and copies the app to
`/Applications`. "Open at login" uses `SMAppService.mainApp` (`System/LoginItem.swift`), which
requires the app to live in a stable location.

Source layout groups by concern: `App/` (entry, delegate, status item), `Core/` (state machine, watchdog, duration model, hold tracker, log), `Input/` (policy, tap, shared state), `Permissions/`, `System/` (browser detection, wake/secure-input), `UI/` (HUD, arming).
