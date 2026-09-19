//
//  AppDelegate.swift
//  LectureLock
//

import AppKit
import Dispatch

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let lockController = LockController()
    private var statusItemController: StatusItemController?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(controller: lockController)
        installSignalHandlers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        lockController.terminate(reason: .appQuit)
    }

    /// SIGTERM / SIGINT (e.g. `killall LectureLock`, Xcode stop) must release input
    /// and write the session log before the process goes away. SIGKILL is not
    /// handled on purpose: macOS removes the tap with the process.
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.lockController.terminate(reason: .signal)
                NSApp.terminate(nil)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
