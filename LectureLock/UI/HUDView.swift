//
//  HUDView.swift
//  LectureLock
//

import SwiftUI

/// Remaining time plus the permanent "hold esc to exit" line. During an Escape
/// hold it shows a filling ring and a descending count. Nothing else animates.
struct HUDView: View {
    @ObservedObject var controller: LockController

    private var hud: LockController.HUDSnapshot { controller.hud }

    private var timeText: String {
        let total = hud.remainingSeconds
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        HStack(spacing: 12) {
            if hud.escapeProgress > 0 {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.2), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: hud.escapeProgress)
                        .stroke(Color.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(hud.escapeRemainingSeconds)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 30, height: 30)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(timeText)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text("hold esc to exit")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
                if hud.dryRun {
                    Text("dry run — input not blocked")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                if hud.secureInputEnabled {
                    Text("secure input on — esc may not register")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 220, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .animation(nil, value: hud)
    }
}
