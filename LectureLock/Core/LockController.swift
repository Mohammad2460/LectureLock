//
//  LockController.swift
//  LectureLock
//

import AppKit
import ApplicationServices
import Combine

/// The single state machine. Every transition happens here, on the main thread.
///
/// Release is one code path for every cause (`release(_:)`): disable and tear
/// down the tap, then timers, then the HUD, then write the session log.
final class LockController: ObservableObject {
    /// Live values for the HUD, updated 10×/s while locked.
    struct HUDSnapshot: Equatable {
        var remainingSeconds: Int = 0
        var escapeProgress: Double = 0
        var escapeRemainingSeconds: Int = 0
        var secureInputEnabled: Bool = false
        var dryRun: Bool = false
    }

    private struct Session {
        let context: TapContext
        let tap: EventTap
        let watchdog: Watchdog
        let start: Date
        let deadline: Date
        let duration: SessionDuration
        let whitelist: Whitelist
        let allowVolumeKeys: Bool
        let showHUD: Bool
        let dryRun: Bool
    }

    @Published private(set) var state: LockState = .idle
    @Published private(set) var lastError: String?
    @Published private(set) var hud = HUDSnapshot()
    @Published private(set) var stats = SessionStats()

    let permission = AccessibilityPermission()

    private var session: Session?
    private var hudTimer: Timer?
    private var hudPanel: HUDPanelController?
    private let log = SessionLog()
    private var wakeObserver: NSObjectProtocol?

    var isDryRun: Bool { session?.dryRun ?? false }

    init() {
        refreshStats()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWake() }
        }
    }

    // MARK: - Arming

    /// Starts the 400 ms settle delay, then re-verifies and enables the tap.
    func arm(
        duration: SessionDuration,
        whitelist: Whitelist,
        allowVolumeKeys: Bool,
        showHUD: Bool,
        dryRun: Bool
    ) {
        guard state == .idle else { return }
        lastError = nil
        state = .arming
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) { [weak self] in
            self?.finishArming(
                duration: duration,
                whitelist: whitelist,
                allowVolumeKeys: allowVolumeKeys,
                showHUD: showHUD,
                dryRun: dryRun
            )
        }
    }

    func cancelArming() {
        guard state == .arming else { return }
        state = .idle
    }

    private func finishArming(
        duration: SessionDuration,
        whitelist: Whitelist,
        allowVolumeKeys: Bool,
        showHUD: Bool,
        dryRun: Bool
    ) {
        guard state == .arming else { return }

        guard AXIsProcessTrusted() else {
            failArming("Accessibility permission is not granted.")
            return
        }
        guard BrowserDetector.isBrowserFrontmost else {
            let name = BrowserDetector.frontmostAppName ?? "another app"
            failArming("\(name) is in front, not a browser. Click your video, then arm again.")
            return
        }

        let context = TapContext(
            whitelist: whitelist,
            allowVolumeKeys: allowVolumeKeys,
            passThrough: dryRun
        )
        guard let tap = EventTap(context: context) else {
            failArming("Couldn't create the event tap. Re-check Accessibility permission.")
            return
        }

        let start = Date()
        // Deadline computed once, here. Nothing accumulates elapsed ticks later.
        let deadline = start.addingTimeInterval(duration.timeInterval)
        let watchdog = Watchdog(context: context, deadline: deadline) { [weak self] reason in
            DispatchQueue.main.async {
                self?.release(reason)
            }
        }

        session = Session(
            context: context,
            tap: tap,
            watchdog: watchdog,
            start: start,
            deadline: deadline,
            duration: duration,
            whitelist: whitelist,
            allowVolumeKeys: allowVolumeKeys,
            showHUD: showHUD,
            dryRun: dryRun
        )

        // Watchdog first: it must already be armed before anything can block input.
        watchdog.start()
        tap.enable()
        presentHUD()
        state = .locked
    }

    private func failArming(_ message: String) {
        lastError = message
        state = .idle
    }

    // MARK: - Release (single path)

    func release(_ reason: ReleaseReason) {
        guard let session else {
            if state == .arming { state = .idle }
            return
        }
        let isTerminating = (state == .terminating)
        if !isTerminating { state = .releasing }

        // 1. Input first, always.
        _ = session.context.claimRelease()
        session.tap.invalidate()

        // 2. Timers.
        session.watchdog.cancel()
        hudTimer?.invalidate()
        hudTimer = nil

        // 3. HUD.
        hudPanel?.hide()
        hudPanel = nil
        hud = HUDSnapshot()

        // 4. Log.
        let actual = Int(Date().timeIntervalSince(session.start).rounded())
        log.append(SessionRecord(
            start: session.start,
            plannedSeconds: session.duration.seconds,
            actualSeconds: max(0, actual),
            releaseMethod: reason,
            whitelist: session.whitelist.rawValue,
            dryRun: session.dryRun
        ))

        self.session = nil
        refreshStats()
        // Surface unexpected endings, so an early release is never silent.
        switch reason {
        case .tapTimeout:
            lastError = "macOS disabled the input tap (too slow) more than 3 times, so the lock ended early."
        case .tapDisabledByUserInput:
            lastError = "macOS disabled the input tap, so the lock ended early."
        default:
            break
        }
        state = isTerminating ? .terminating : .idle
    }

    /// App quit or SIGTERM. Releases input, then leaves the machine in `.terminating`.
    func terminate(reason: ReleaseReason) {
        state = .terminating
        release(reason)
    }

    // MARK: - Stats

    /// Re-reads the session log. Cheap (a few KB); called at launch, after every
    /// release and when the panel opens, so "today" follows the calendar.
    func refreshStats() {
        let fresh = SessionStats.compute(records: log.readAll(), now: Date(), calendar: .current)
        if fresh != stats { stats = fresh }
    }

    // MARK: - Sleep / wake

    private func handleWake() {
        guard let session, state == .locked else { return }
        if Date() >= session.deadline {
            release(.wakeAfterDeadline)
            return
        }
        // Tap can come back from sleep disabled; re-arm it within the same budget.
        if !session.tap.isEnabled {
            let mayReenable = session.context.withState { $0.registerTimeout() }
            if mayReenable {
                session.tap.enable()
            } else {
                release(.tapTimeout)
            }
        }
    }

    // MARK: - HUD

    private func presentHUD() {
        updateHUD()
        let panel = HUDPanelController(controller: self)
        panel.setVisible(session?.showHUD ?? true)
        hudPanel = panel

        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHUD() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hudTimer = timer
    }

    private func updateHUD() {
        guard let session else { return }
        let now = EscapeHoldTracker.now()
        let (progress, heldNanos) = session.context.withState { state in
            (state.escape.progress(at: now), state.escape.heldNanos(at: now))
        }
        let remainingHold = EscapeHoldTracker.requiredHoldNanos > heldNanos
            ? EscapeHoldTracker.requiredHoldNanos - heldNanos
            : 0

        var snapshot = HUDSnapshot()
        snapshot.remainingSeconds = max(0, Int(session.deadline.timeIntervalSinceNow.rounded(.up)))
        snapshot.escapeProgress = progress
        snapshot.escapeRemainingSeconds = Int((Double(remainingHold) / 1_000_000_000).rounded(.up))
        snapshot.secureInputEnabled = SecureInput.isEnabled
        snapshot.dryRun = session.dryRun
        if snapshot != hud { hud = snapshot }
        // Hidden HUD still surfaces while Escape is held.
        hudPanel?.setVisible(session.showHUD || snapshot.escapeProgress > 0)
    }
}
