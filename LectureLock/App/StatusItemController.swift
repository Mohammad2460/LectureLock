//
//  StatusItemController.swift
//  LectureLock
//

import AppKit
import Combine

/// Owns the menu-bar icon. A click toggles the arming panel; the icon reflects
/// lock state. No menu, so clicking never activates the app and the browser
/// stays frontmost.
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let controller: LockController
    private let armingPanel: ArmingPanelController
    private var stateObserver: AnyCancellable?

    init(controller: LockController) {
        self.controller = controller
        armingPanel = ArmingPanelController(controller: controller)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.setButtonType(.momentaryChange)
        }

        stateObserver = controller.$state.sink { [weak self] state in
            self?.updateIcon(for: state)
        }
        updateIcon(for: controller.state)
    }

    private func updateIcon(for state: LockState) {
        guard let button = statusItem.button else { return }
        let symbol: String
        switch state {
        case .idle, .terminating: symbol = "lock.open"
        case .arming, .releasing: symbol = "lock.rotation"
        case .locked: symbol = "lock.fill"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "LectureLock")
            ?? NSImage(systemSymbolName: "lock", accessibilityDescription: "LectureLock")
        image?.isTemplate = true
        button.image = image
    }

    @objc private func togglePanel() {
        armingPanel.toggle(relativeTo: statusItem.button)
    }
}
