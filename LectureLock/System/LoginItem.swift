//
//  LoginItem.swift
//  LectureLock
//

import Combine
import ServiceManagement

/// "Open at login", via `SMAppService` (macOS 13+). No helper bundle needed: the
/// app registers itself.
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled: Bool

    init() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    func refresh() {
        let enabled = (SMAppService.mainApp.status == .enabled)
        if enabled != isEnabled { isEnabled = enabled }
    }

    /// Returns an error message on failure, nil on success.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
            return nil
        } catch {
            refresh()
            // Registering only works for an app in a stable location, e.g. /Applications.
            return "Couldn't change the login item: \(error.localizedDescription)"
        }
    }
}
