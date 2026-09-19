//
//  SessionDurationTests.swift
//  LectureLockTests
//

import Testing

@testable import LectureLock

@Suite("Session duration")
struct SessionDurationTests {
    @Test("The 90-minute cap is enforced in the model")
    func hardCap() {
        #expect(SessionDuration(minutes: 91).wholeMinutes == 90)
        #expect(SessionDuration(minutes: 10_000).seconds == 90 * 60)
        #expect(SessionDuration(seconds: 100_000).seconds == 90 * 60)
    }

    @Test("Durations below the minimum clamp up, never to zero or negative")
    func lowerBound() {
        #expect(SessionDuration(minutes: 0).wholeMinutes == 1)
        #expect(SessionDuration(minutes: -5).wholeMinutes == 1)
        #expect(SessionDuration(seconds: 0).seconds == 1)
        #expect(SessionDuration(seconds: -1).seconds == 1)
    }

    @Test("Values in range are kept")
    func inRange() {
        #expect(SessionDuration(minutes: 45).seconds == 2700)
        #expect(SessionDuration(seconds: 30).seconds == 30)
        #expect(SessionDuration(minutes: 90).seconds == 5400)
    }
}
