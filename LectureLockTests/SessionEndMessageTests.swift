//
//  SessionEndMessageTests.swift
//  LectureLockTests
//

import Testing

@testable import LectureLock

@Suite("Session end message")
struct SessionEndMessageTests {
    @Test("Planned endings report the time done")
    func planned() {
        #expect(SessionEndMessage.text(for: .deadline, actualSeconds: 45 * 60, dryRun: false)
            == "Lock ended — 45 min done.")
        #expect(SessionEndMessage.text(for: .wakeAfterDeadline, actualSeconds: 45 * 60, dryRun: false)
            == "Lock ended — 45 min done.")
    }

    @Test("Escape hold says it ended early and when")
    func escape() {
        #expect(SessionEndMessage.text(for: .escapeHold, actualSeconds: 23 * 60 + 10, dryRun: false)
            == "Lock ended early (esc held) after 23 min.")
    }

    @Test("Tap failures say macOS ended it")
    func tapFailures() {
        let expected = "Lock ended early — macOS disabled the input tap."
        #expect(SessionEndMessage.text(for: .tapTimeout, actualSeconds: 60, dryRun: false) == expected)
        #expect(SessionEndMessage.text(for: .tapDisabledByUserInput, actualSeconds: 60, dryRun: false) == expected)
    }

    @Test("Quitting gives no cue")
    func quitting() {
        #expect(SessionEndMessage.text(for: .appQuit, actualSeconds: 60, dryRun: false) == nil)
        #expect(SessionEndMessage.text(for: .signal, actualSeconds: 60, dryRun: false) == nil)
    }

    @Test("Short sessions round to at least one minute")
    func minimumMinute() {
        #expect(SessionEndMessage.text(for: .deadline, actualSeconds: 20, dryRun: false)
            == "Lock ended — 1 min done.")
    }

    @Test("Dry runs are labelled")
    func dryRun() {
        #expect(SessionEndMessage.text(for: .endedFromMenu, actualSeconds: 120, dryRun: true)
            == "Dry run ended after 2 min.")
        #expect(SessionEndMessage.text(for: .deadline, actualSeconds: 120, dryRun: true)
            == "Lock ended — 2 min done. (dry run)")
    }
}
