//
//  LectureLockApp.swift
//  LectureLock
//

import SwiftUI

@main
struct LectureLockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu-bar only app (LSUIElement). No windows are declared here;
        // all UI is driven from the status item via AppKit.
        Settings {
            EmptyView()
        }
    }
}
