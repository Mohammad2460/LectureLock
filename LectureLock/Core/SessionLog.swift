//
//  SessionLog.swift
//  LectureLock
//

import Foundation

nonisolated struct SessionRecord: Codable, Equatable, Sendable {
    var start: Date
    var plannedSeconds: Int
    var actualSeconds: Int
    var releaseMethod: ReleaseReason
    var whitelist: Int
    var dryRun: Bool
}

/// One JSON object per line at
/// `~/Library/Application Support/LectureLock/sessions.jsonl`. Local only —
/// nothing is ever sent anywhere.
struct SessionLog {
    static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LectureLock", isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent("sessions.jsonl", isDirectory: false)
    }

    func append(_ record: SessionRecord) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var data = try? encoder.encode(record) else { return }
        data.append(0x0A)

        let fm = FileManager.default
        let url = Self.fileURL
        do {
            try fm.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) {
                try data.write(to: url, options: .atomic)
            } else {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            }
        } catch {
            // A failed log write must never affect releasing input.
            NSLog("LectureLock: could not write session log: \(error.localizedDescription)")
        }
    }
}
