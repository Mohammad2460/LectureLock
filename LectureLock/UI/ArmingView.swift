//
//  ArmingView.swift
//  LectureLock
//

import SwiftUI

struct ArmingView: View {
    @ObservedObject var controller: LockController
    @ObservedObject var permission: AccessibilityPermission
    @ObservedObject var browser: BrowserDetector
    @ObservedObject var loginItem: LoginItem
    let dismiss: () -> Void

    @AppStorage("durationMinutes") private var durationMinutes = 45
    @AppStorage("whitelist") private var whitelistRaw = Whitelist.jkl.rawValue
    @AppStorage("dryRun") private var dryRun = false
    @AppStorage("allowVolumeKeys") private var allowVolumeKeys = true
    @AppStorage("showHUD") private var showHUD = false

    @State private var customText = ""
    @State private var clickedVideo = false
    @State private var loginItemError: String?

    private var whitelist: Whitelist { Whitelist(rawValue: whitelistRaw) ?? .jkl }
    private var duration: SessionDuration { SessionDuration(minutes: durationMinutes) }

    private var isReady: Bool {
        permission.isGranted && browser.isBrowserFrontmost && clickedVideo && controller.state == .idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch controller.state {
            case .locked, .releasing:
                lockedSection
            case .arming:
                Text("Arming… keep your browser in front.")
                    .font(.callout)
            case .idle, .terminating:
                armingSection
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: - Locked

    private var lockedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Locked")
                .font(.headline)
            Text("Hold **esc** for 30 seconds to end early.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if controller.isDryRun {
                Button("End dry run") {
                    controller.release(.endedFromMenu)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Arming

    private var armingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Duration")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    ForEach(SessionDuration.presetMinutes, id: \.self) { minutes in
                        Button("\(minutes)") {
                            durationMinutes = minutes
                            customText = ""
                        }
                        .buttonStyle(.bordered)
                        .tint(durationMinutes == minutes && customText.isEmpty ? .accentColor : nil)
                    }
                    Spacer(minLength: 4)
                    TextField("custom", text: $customText)
                        .frame(width: 52)
                        .multilineTextAlignment(.trailing)
                        .onSubmit(applyCustom)
                        .onChange(of: customText) { _ in applyCustom() }
                    Text("min")
                        .foregroundStyle(.secondary)
                }
                Text("1–90 minutes. Hard cap: 90.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Keys that still work")
                    .font(.subheadline.weight(.semibold))
                Picker("", selection: $whitelistRaw) {
                    ForEach(Whitelist.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Toggle(isOn: $allowVolumeKeys) {
                    Text("Volume up / down / mute")
                }
                .toggleStyle(.checkbox)
                .font(.callout)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Before arming")
                    .font(.subheadline.weight(.semibold))
                checkRow(done: permission.isGranted, text: "Accessibility permission") {
                    HStack(spacing: 6) {
                        Button("Grant") { permission.requestPrompt() }
                            .buttonStyle(.link)
                        Button("Settings") { permission.openSystemSettings() }
                            .buttonStyle(.link)
                    }
                }
                checkRow(
                    done: browser.isBrowserFrontmost,
                    text: browser.isBrowserFrontmost
                        ? "\(browser.frontmostName ?? "Browser") is in front"
                        : "Bring your browser to the front (\(browser.frontmostName ?? "—") is)"
                )
                Toggle(isOn: $clickedVideo) {
                    Text("I clicked the video")
                }
                .toggleStyle(.checkbox)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $showHUD) {
                    Text("Show countdown HUD")
                }
                .toggleStyle(.checkbox)
                .font(.callout)
                Text("Off: the HUD appears only while you hold esc.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(isOn: $dryRun) {
                    Text("Dry run (evaluate, don't block)")
                }
                .toggleStyle(.checkbox)
                .font(.callout)
            }

            Toggle(isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItemError = loginItem.setEnabled($0) }
            )) {
                Text("Open LectureLock at login")
            }
            .toggleStyle(.checkbox)
            .font(.callout)

            if let loginItemError {
                Text(loginItemError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.link)
                Spacer()
                Button("Lock for \(duration.wholeMinutes) min") {
                    controller.arm(
                        duration: duration,
                        whitelist: whitelist,
                        allowVolumeKeys: allowVolumeKeys,
                        showHUD: showHUD,
                        dryRun: dryRun
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isReady)
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            clickedVideo = false
            loginItem.refresh()
        }
    }

    private func checkRow(
        done: Bool,
        text: String,
        @ViewBuilder accessory: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !done { accessory() }
        }
    }

    private func applyCustom() {
        let digits = customText.filter(\.isNumber)
        if digits != customText { customText = digits }
        guard let value = Int(digits), value > 0 else { return }
        let clamped = SessionDuration(minutes: value)
        durationMinutes = clamped.wholeMinutes
        if String(clamped.wholeMinutes) != digits { customText = String(clamped.wholeMinutes) }
    }
}
