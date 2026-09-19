//
//  HUDPanel.swift
//  LectureLock
//

import AppKit
import SwiftUI

/// Borderless, non-activating panel in the top-right corner. It never takes key
/// or main status and ignores mouse events, so it cannot steal focus from the
/// browser or swallow a click.
final class HUDPanelController {
    private let panel: NSPanel
    private let hostingView: NSHostingView<HUDView>
    private var frameObserver: NSObjectProtocol?

    private static let inset: CGFloat = 20

    init(controller: LockController) {
        hostingView = NSHostingView(rootView: HUDView(controller: controller))
        hostingView.sizingOptions = [.intrinsicContentSize]

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 210, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
    }

    /// With the countdown HUD switched off the panel still exists but stays hidden;
    /// it is shown only while Escape is held, so the hold always has feedback.
    func setVisible(_ visible: Bool) {
        guard visible != panel.isVisible else { return }
        if visible {
            reposition()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
        // Keep the panel pinned to the top-right as its content grows or shrinks.
        hostingView.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: hostingView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    func hide() {
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        frameObserver = nil
        panel.orderOut(nil)
    }

    deinit {
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
    }

    private func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - size.width - Self.inset,
            y: visible.maxY - size.height - Self.inset
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
