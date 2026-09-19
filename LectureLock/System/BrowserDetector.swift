//
//  BrowserDetector.swift
//  LectureLock
//

import AppKit
import Combine

/// Live "is a browser frontmost?" readiness check for the arming window.
final class BrowserDetector: ObservableObject {
    static let browserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.microsoft.edgemac",
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "company.thebrowser.Browser", // Arc
        "company.thebrowser.dia",
        "ai.perplexity.comet", // Comet
        "com.openai.atlas", // ChatGPT Atlas
        "com.sigmaos.sigmaos.stable",
        "net.whatwg.orion",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "app.zen-browser.zen",
    ]

    @Published private(set) var frontmostName: String?
    @Published private(set) var isBrowserFrontmost = false

    private var observer: NSObjectProtocol?
    private var timer: Timer?

    /// Snapshot check used by the arming flow (no observation required).
    static var isBrowserFrontmost: Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let id = app.bundleIdentifier else { return false }
        return browserBundleIDs.contains(id)
    }

    static var frontmostAppName: String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    func startMonitoring() {
        refresh()
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // The panel is non-activating, so our own app never becomes frontmost; poll
        // as a backstop for window-level focus changes the notification misses.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopMonitoring() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        let name = Self.frontmostAppName
        let isBrowser = Self.isBrowserFrontmost
        if name != frontmostName { frontmostName = name }
        if isBrowser != isBrowserFrontmost { isBrowserFrontmost = isBrowser }
    }
}
