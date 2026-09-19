//
//  TapStateTests.swift
//  LectureLockTests
//

import Testing

@testable import LectureLock

@Suite("Tap state")
struct TapStateTests {
    @Test("The tap may be re-enabled after a timeout at most three times, then releases")
    func timeoutBudget() {
        var state = TapState(whitelist: .jkl, allowVolumeKeys: true, passThrough: false)
        var results: [Bool] = []
        for _ in 0..<4 { results.append(state.registerTimeout()) }
        #expect(results == [true, true, true, false])
        #expect(state.pendingRelease == .tapTimeout)
    }

    @Test("Our own tapEnable(false) notice re-enables instead of ending the session")
    func expectedDisableNoticeIsNotFatal() {
        var state = TapState(whitelist: .jkl, allowVolumeKeys: true, passThrough: false)
        state.expectedDisableNotices = 1
        let reenable = state.handleUserInputDisable()
        #expect(reenable)
        #expect(state.pendingRelease == nil)
        #expect(state.expectedDisableNotices == 0)
    }

    @Test("A disable macOS caused ends the session")
    func unexpectedDisableReleases() {
        var state = TapState(whitelist: .jkl, allowVolumeKeys: true, passThrough: false)
        let reenable = state.handleUserInputDisable()
        #expect(!reenable)
        #expect(state.pendingRelease == .tapDisabledByUserInput)
    }

    @Test("A disable notice after release is ignored")
    func disableAfterReleaseIgnored() {
        var state = TapState(whitelist: .jkl, allowVolumeKeys: true, passThrough: false)
        state.isReleased = true
        let reenable = state.handleUserInputDisable()
        #expect(!reenable)
        #expect(state.pendingRelease == nil)
    }

    @Test("The first release reason wins")
    func firstReasonWins() {
        var state = TapState(whitelist: .jkl, allowVolumeKeys: true, passThrough: false)
        state.requestRelease(.tapDisabledByUserInput)
        state.requestRelease(.tapTimeout)
        #expect(state.pendingRelease == .tapDisabledByUserInput)
    }

    @Test("Only one caller can claim the release")
    func claimReleaseIsExclusive() {
        let context = TapContext(whitelist: .jkl, allowVolumeKeys: true, passThrough: false)
        let first = context.claimRelease()
        let second = context.claimRelease()
        #expect(first)
        #expect(!second)
        #expect(context.withState { $0.isReleased })
    }

    @Test("A released session stops re-enabling the tap")
    func releasedStateRefusesTimeout() {
        var state = TapState(whitelist: .jkl, allowVolumeKeys: true, passThrough: false)
        state.isReleased = true
        let allowed = state.registerTimeout()
        #expect(!allowed)
    }
}
