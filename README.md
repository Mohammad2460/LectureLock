# LectureLock

A tiny macOS menu-bar app that locks your keyboard and mouse while you watch a
lecture, so you can't reflexively switch tabs.

Only the keys you pick get through — `j` / `k` / `l`, or `Space` / `←` / `→`,
plus volume up / down / mute if you want them. Cursor movement stays free;
clicks, scrolling, `⌘Tab`, trackpad swipes and every other key are swallowed for
the duration you set.

LectureLock never touches the video or the browser. It only filters input.

## Safety guarantees

These come first; every feature is built behind them.

- **It always ends on time.** A watchdog on its own dispatch queue disables the
  event tap at the deadline regardless of what the UI is doing. The deadline is
  computed once, from a single `Date()` at arm time — nothing accumulates ticks.
- **Emergency exit:** hold `esc` for 30 seconds. Measured by wall clock between
  key-down and key-up, ignoring auto-repeat, and reset by an early release.
- **Hard cap of 90 minutes**, enforced in the model, not just the text field.
- **It never fights the OS.** Force Quit and logging out are never disabled. If
  the app crashes or is killed, macOS removes the tap and input returns to
  normal. That is a deliberate escape hatch, not a bug.
- **Sleep-safe:** on wake, the deadline is re-checked and the session released if
  it has passed.
- **Nothing leaves your machine.** One JSON line per session to
  `~/Library/Application Support/LectureLock/sessions.jsonl`, and that's it. No
  network code.

## Install

macOS 13 or later, Apple silicon or Intel. There is no notarized release build
and no DMG: this is a single-user tool that needs Accessibility permission, so
you build it yourself and keep it in `/Applications`.

```sh
git clone https://github.com/Mohammad2460/LectureLock.git
cd LectureLock
./scripts/install.sh "LectureLock Dev"   # identity optional, see below
```

Then click the menu-bar lock icon, press **Grant** to give Accessibility
permission, and tick **Open LectureLock at login**. Done — you never need Xcode
again unless you change the code.

### Signing identity (optional but recommended)

macOS ties Accessibility permission to an app's code signature. An ad-hoc
signature changes on every build, so macOS forgets the grant each time. For a
one-off install that doesn't matter. If you plan to rebuild, create a free
self-signed certificate once:

1. Keychain Access → **Certificate Assistant → Create a Certificate…**
2. Name `LectureLock Dev`, Identity Type **Self-Signed Root**, Certificate Type
   **Code Signing**.
3. Pass that name to `install.sh`, or set it as the Debug signing identity in
   Xcode.

## How to use it

1. Click the lock icon in the menu bar. A panel opens under it — it never steals
   focus, so your browser stays in front.
2. Pick a duration: 25 / 45 / 60 / 90, or type any number of minutes up to 90.
3. Pick which keys stay alive, and whether volume keys keep working.
4. Clear the three readiness checks: Accessibility granted, a browser in front,
   and "I clicked the video". The Lock button stays disabled until all three
   pass.
5. Press Lock. After a 400 ms settle it re-verifies that a browser is still in
   front, then the tap goes live.

**The countdown HUD is off by default**, so nothing sits on your screen while you
watch. It still appears while you hold `esc`, so the emergency hold always shows
its progress. Turn it on in the panel if you want the timer visible.

**Dry run** runs the entire session — watchdog, HUD, Escape hold, session log —
but forwards every event instead of blocking it. Use it to test changes without
locking yourself out.

### Ways a session ends

| Cause | Note |
| --- | --- |
| Duration elapses | Wall-clock watchdog timer on its own queue |
| `esc` held 30 s | Ring and countdown appear while held |
| Wake from sleep past the deadline | Checked on `didWakeNotification` |
| macOS disables the tap | Re-enabled at most 3× per session, then released |
| Quit / SIGTERM / SIGINT | Input released and the session logged first |
| Crash or SIGKILL | macOS removes the tap; nothing to clean up |

`esc` is never forwarded to the browser while locked. If secure input is active
(a password field somewhere has focus) the tap cannot see keystrokes at all —
the HUD says so, and the deadline still ends the session.

## How it works

One `CGEventTap` at `.cghidEventTap`, `.headInsertEventTap`. It must be the HID
tap: the session tap sits after the WindowServer has already handled `⌘Tab`, so
it would let it through. Because the tap blocks both keyboard and mouse, the
browser keeps focus the whole time and no overlay window is needed.

- `Input/KeyPolicy.swift` — the entire policy as one pure, unit-tested function.
  Whitelist only, never a denylist: anything not explicitly allowed is blocked.
- `Input/EventTap.swift` — the tap and its callback. The callback runs on every
  system-wide input event, so it allocates nothing, logs nothing, takes no locks
  beyond one `os_unfair_lock`, and touches no UI.
- `Input/TapSharedState.swift` — the one POD struct shared between the callback,
  the watchdog queue and the main thread.
- `Core/LockController.swift` — the single state machine
  (`idle → arming → locked → releasing → idle`, plus `terminating`). Release is
  one code path for every cause: tap first, then timers, then HUD, then log.
- `Core/Watchdog.swift` — deadline timer plus a 100 ms poll for the Escape hold
  and release requests, on a dedicated queue. It disables the tap itself, so
  even a hung main thread cannot keep input locked.

Views are SwiftUI; windows, the status item and the tap are AppKit. App Sandbox
is off (event taps require it) and Hardened Runtime is on.

## Development

```sh
xcodebuild -project LectureLock.xcodeproj -scheme LectureLock -configuration Debug build
xcodebuild test -project LectureLock.xcodeproj -scheme LectureLock -destination 'platform=macOS'
```

The tests cover the key policy, the 90-minute cap, the Escape-hold tracker's
edge cases and the tap's re-enable budget — the parts where a mistake either
locks you out or fails to lock at all. Behaviour that can't be tested without
taking over the machine (actual blocking, HUD placement, panel focus) is what
dry run is for.

`CLAUDE.md` documents the invariants in more detail; read it before changing
anything in `Input/` or `Core/`.

## Contributing

Issues and pull requests are welcome. Two rules:

1. Never weaken a safety guarantee above. In particular, don't add
   `disableForceQuit` or `disableSessionTermination`, and don't make the app
   defend against being killed.
2. Keep the tap callback allocation-free and keep the key policy a pure
   function with tests.

## License

MIT — see [LICENSE](LICENSE).
