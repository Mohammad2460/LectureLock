//
//  SessionEndNotifier.swift
//  LectureLock
//

import AppKit
import Combine
import UserNotifications

/// What the end-of-session banner says. Pure, so every release reason is tested.
nonisolated enum SessionEndMessage {
    /// `nil` means no cue: the app is quitting, so there is nothing to tell.
    static func text(for reason: ReleaseReason, actualSeconds: Int, dryRun: Bool) -> String? {
        let minutes = max(1, Int((Double(actualSeconds) / 60).rounded()))
        let base: String
        switch reason {
        case .deadline, .wakeAfterDeadline:
            base = "Lock ended — \(minutes) min done."
        case .escapeHold:
            base = "Lock ended early (esc held) after \(minutes) min."
        case .tapTimeout, .tapDisabledByUserInput:
            base = "Lock ended early — macOS disabled the input tap."
        case .endedFromMenu:
            return "Dry run ended after \(minutes) min."
        case .appQuit, .signal:
            return nil
        }
        return dryRun ? base + " (dry run)" : base
    }
}

/// Sound + banner when a lock ends, so an unlock is never silent.
///
/// Runs only after input has been released and the session logged: nothing here
/// can delay or prevent a release.
final class SessionEndNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// The user turned notifications off for LectureLock; only the sound plays.
    var isDenied: Bool { authorization == .denied }

    private var center: UNUserNotificationCenter { .current() }

    override init() {
        super.init()
        center.delegate = self
        refreshAuthorization()
    }

    func refreshAuthorization() {
        Task {
            let status = await center.notificationSettings().authorizationStatus
            if status != authorization { authorization = status }
        }
    }

    /// Asks for permission if never asked. Only called from the panel (box ticked,
    /// or panel opened with it ticked), never while arming, so the system prompt
    /// can't pull focus away from the browser at the moment of locking.
    func requestAuthorizationIfNeeded() {
        Task {
            guard await center.notificationSettings().authorizationStatus == .notDetermined else {
                refreshAuthorization()
                return
            }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            refreshAuthorization()
        }
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        NSWorkspace.shared.open(url)
    }

    func sessionEnded(reason: ReleaseReason, actualSeconds: Int, dryRun: Bool) {
        guard let text = SessionEndMessage.text(for: reason, actualSeconds: actualSeconds, dryRun: dryRun) else {
            return
        }
        // Sound plays even when notifications are denied.
        NSSound(named: "Glass")?.play()

        let content = UNMutableNotificationContent()
        content.title = "LectureLock"
        content.body = text
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error { NSLog("LectureLock: could not post notification: \(error.localizedDescription)") }
        }
    }

    // Show the banner even if LectureLock happens to be the active app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
