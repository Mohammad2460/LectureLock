//
//  AccessibilityPermission.swift
//  LectureLock
//

import AppKit
import ApplicationServices
import Combine

/// Live view of the Accessibility (TCC) grant needed to create a blocking event tap.
///
/// macOS posts no reliable notification when the grant changes, so while someone
/// is watching (`startMonitoring`) the status is polled once a second.
final class AccessibilityPermission: ObservableObject {
    @Published private(set) var isGranted: Bool = AXIsProcessTrusted()

    private var timer: Timer?
    private var watchers = 0

    /// Shows the system "would like to control this computer" prompt if not yet granted.
    func requestPrompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        isGranted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Opens System Settings → Privacy & Security → Accessibility.
    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func refresh() {
        let granted = AXIsProcessTrusted()
        if granted != isGranted { isGranted = granted }
    }

    func startMonitoring() {
        watchers += 1
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopMonitoring() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }
}
