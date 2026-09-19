//
//  ArmingPanel.swift
//  LectureLock
//

import AppKit
import SwiftUI

/// Non-activating panel anchored under the menu-bar icon.
///
/// Non-activating matters: the readiness check requires a browser to be
/// frontmost, and arming re-verifies that 400 ms later. A normal window would
/// activate LectureLock and break both.
private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

final class ArmingPanelController {
    private let panel: NonActivatingPanel
    private let controller: LockController
    private let browser = BrowserDetector()
    private let loginItem = LoginItem()

    var isVisible: Bool { panel.isVisible }

    init(controller: LockController) {
        self.controller = controller

        panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 380),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "LectureLock"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false

        let view = ArmingView(
            controller: controller,
            permission: controller.permission,
            browser: browser,
            loginItem: loginItem,
            dismiss: { [weak panel] in panel?.orderOut(nil) }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
    }

    func toggle(relativeTo statusButton: NSStatusBarButton?) {
        if panel.isVisible {
            hide()
        } else {
            show(relativeTo: statusButton)
        }
    }

    func show(relativeTo statusButton: NSStatusBarButton?) {
        controller.permission.startMonitoring()
        browser.startMonitoring()
        position(relativeTo: statusButton)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hide() {
        controller.permission.stopMonitoring()
        browser.stopMonitoring()
        panel.orderOut(nil)
    }

    private func position(relativeTo statusButton: NSStatusBarButton?) {
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        panel.setContentSize(size)
        guard let buttonFrame = statusButton?.window?.frame,
              let screen = statusButton?.window?.screen ?? NSScreen.main else {
            panel.center()
            return
        }
        var origin = NSPoint(
            x: buttonFrame.midX - panel.frame.width / 2,
            y: buttonFrame.minY - panel.frame.height - 6
        )
        origin.x = min(max(origin.x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - panel.frame.width - 8)
        panel.setFrameOrigin(origin)
    }
}
