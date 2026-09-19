//
//  SecureInput.swift
//  LectureLock
//

import Carbon.HIToolbox

/// While secure event input is on (a password field somewhere has focus), event
/// taps stop seeing keystrokes — including the Escape hold. The HUD says so, and
/// the watchdog deadline still ends the session regardless.
nonisolated enum SecureInput {
    static var isEnabled: Bool { IsSecureEventInputEnabled() }
}
