// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 duderayuh
//
// Headless programming path.
//
//   Mini5Forge --program <channels.csv> [--dry-run] [--device <name fragment>] [--out <dir>]
//
// Reads the radio first (so its settings/VFO/DTMF survive), replaces the channel list from the
// CSV, writes, then reads back and diffs. Always writes a pre-flight backup.

import Foundation
import CoreBluetooth
import AppKit

@MainActor
final class Programmer {

    private let link = RadioLink()
    private var finished = false

    /// Matches a discovered radio by BLE identifier (first 8+ hex chars) or by advertised name.
    private func matches(_ radio: DiscoveredRadio, deviceMatch: String?, deviceID: String?) -> Bool {
        if let deviceID {
            return radio.id.uuidString.lowercased().hasPrefix(deviceID.lowercased())
        }
        if let deviceMatch {
            return radio.name.lowercased().contains(deviceMatch.lowercased())
        }
        return true
    }

    func run(csvPath: String, deviceMatch: String?, deviceID: String?, dryRun: Bool, outDir: String) async -> Int32 {
        link.onLog = { print("  link: \($0)") }
        guard let csvData = FileManager.default.contents(atPath: csvPath),
              let csvText = String(data: csvData, encoding: .utf8) else {
            print("ERROR: cannot read \(csvPath)")
            return 2
        }
        let parsed = ChannelCSV.parse(csvText)
        print("CSV: \(parsed.channels.count) channel(s) parsed from \((csvPath as NSString).lastPathComponent)")
        for warning in parsed.warnings.prefix(10) { print("  note: \(warning)") }
        guard !parsed.channels.isEmpty else {
            print("ERROR: no usable channels in CSV")
            return 2
        }

        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .prefix(15)

        // ---- find the radio ----
        link.startScan()
        var candidate: DiscoveredRadio?
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let pool = link.discovered
            let filtered = pool.filter { self.matches($0, deviceMatch: deviceMatch, deviceID: deviceID) }
            candidate = filtered.first(where: { $0.advertisesProgrammingService })
                ?? filtered.first(where: { radio in
                    let n = radio.name.uppercased()
                    return n.contains("5RMINI") || n.contains("MINI") || n.contains("BAOFENG")
                        || n.contains("UV-5R") || n.contains("BF-")
                })
            if candidate != nil { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard let candidate else {
            print("ERROR: no radio found in 30 s. Devices seen: \(link.discovered.count)")
            for radio in link.discovered { print("   - \(radio.name)  \(radio.rssi) dBm  FFE0=\(radio.advertisesProgrammingService)") }
            link.stopScan()
            return 3
        }
        print("FOUND: \(candidate.name) [id \(candidate.id.uuidString)] (\(candidate.rssi) dBm, FFE0=\(candidate.advertisesProgrammingService))")

        do {
            // ---- read ----
            print("READ: handshake + 521 blocks…")
            var before: RadioImage
            do {
                before = try await link.readAll { done, total in
                    if done == total || done % 128 == 0 { print("   \(done)/\(total) blocks") }
                }
            } catch {
                print("   first attempt failed (\(error.localizedDescription)); reconnecting once…")
                link.disconnect()
                try await Task.sleep(nanoseconds: 2_000_000_000)
                link.startScan()
                var retry: DiscoveredRadio?
                let deadline = Date().addingTimeInterval(20)
                while Date() < deadline {
                    retry = link.discovered.first(where: {
                        $0.advertisesProgrammingService && self.matches($0, deviceMatch: deviceMatch, deviceID: deviceID)
                    })
                    if retry != nil { break }
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
                guard let retry else { throw error }
                print("   reconnecting to \(retry.name)")
                try await link.connect(retry)
                before = try await link.readAll { done, total in
                    if done == total || done % 128 == 0 { print("   \(done)/\(total) blocks") }
                }
            }
            let backupPath = "\(outDir)/MINI5-backup-\(stamp).img"
            try before.fileData.write(to: URL(fileURLWithPath: backupPath))
            print("BACKUP: \(backupPath)")

            // ---- merge CSV into the radio's own configuration ----
            var config = Codec.config(from: before)
            var channels = Array(config.channels.prefix(RadioLayout.usableChannels))
            for (index, channel) in channels.enumerated() {
                var vacant = Channel(slot: index + 1)
                vacant.name = ""
                channels[index] = vacant
            }
            for (index, channel) in parsed.channels.prefix(RadioLayout.usableChannels).enumerated() {
                var copy = channel
                copy.slot = index + 1
                channels[index] = copy
            }
            config.channels = channels

            let plan = Codec.apply(config, to: before)
            let diff = RadioImage.diff(before, plan)
            print("PLAN: \(parsed.channels.count) channels, \(diff.total) byte(s) change")
            for section in diff.sections where section.changed > 0 {
                print("   \(section.title): \(section.changed) byte(s)")
            }
            let planPath = "\(outDir)/MINI5-planned-\(stamp).img"
            try plan.fileData.write(to: URL(fileURLWithPath: planPath))
            print("PLANNED IMAGE: \(planPath)")

            if dryRun {
                print("DRY RUN: nothing written to the radio.")
                link.disconnect()
                return 0
            }

            // ---- write + verify ----
            print("WRITE: 262 blocks…")
            let readback = try await link.writeAll(plan) { done, total in
                if done == total || done % 64 == 0 { print("   \(done)/\(total) blocks") }
            }
            let verify = RadioImage.diff(plan, readback)
            print("VERIFY: \(verify.total) byte(s) differ from the plan")
            let afterPath = "\(outDir)/MINI5-readback-\(stamp).img"
            try readback.fileData.write(to: URL(fileURLWithPath: afterPath))
            print("READBACK: \(afterPath)")

            let verifyConfig = Codec.config(from: readback)
            let populated = verifyConfig.channels.prefix(RadioLayout.usableChannels).filter { !$0.isVacant }
            print("RADIO NOW: \(populated.count) programmed channel(s)")
            print(verify.total == 0 ? "RESULT: verified — radio matches the plan byte for byte."
                                    : "RESULT: MISMATCH — \(verify.total) byte(s) off plan.")
            link.disconnect()
            return verify.total == 0 ? 0 : 1
        } catch {
            print("ERROR: \(error.localizedDescription)")
            link.disconnect()
            return 4
        }
    }
}
