// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 duderayuh
//
// Mini5 Forge — memory inspector, diff and log.

import SwiftUI
import AppKit

struct InspectPane: View {
    @ObservedObject var model: ForgeModel
    @State private var section: RadioLayout.Section = .settings
    @State private var page = 0

    private let pageBytes = 512

    private var sectionLines: [(address: Int, bytes: [UInt8])] {
        guard let image = model.baseImage else { return [] }
        let bounds = section.bounds
        var rows: [(Int, [UInt8])] = []
        var address = bounds.start
        while address < bounds.end {
            let count = min(16, bounds.end - address)
            guard let start = RadioLayout.offset(forAddress: address) else { break }
            rows.append((address, Array(image.bytes[start..<min(start + count, image.bytes.count)])))
            address += count
        }
        return rows
    }

    private var pageCount: Int {
        max(1, (sectionLines.count * 16 + pageBytes - 1) / pageBytes)
    }

    private var visibleLines: [(address: Int, bytes: [UInt8])] {
        let perPage = pageBytes / 16
        let start = page * perPage
        guard start < sectionLines.count else { return [] }
        return Array(sectionLines[start..<min(start + perPage, sectionLines.count)])
    }

    private var diff: ImageDiff? {
        guard let base = model.baseImage, let plan = model.writeCandidate() else { return nil }
        return RadioImage.diff(base, plan)
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeading(title: "Memory inspector",
                        subtitle: "Decoded CPS bytes exactly as the radio stores them, plus the difference your edits would make.")
            Divider()
            HStack(spacing: 12) {
                Picker("Section", selection: $section) {
                    ForEach(RadioLayout.Section.allCases) { Text($0.title).tag($0) }
                }
                .frame(width: 220)
                .onChange(of: section) { _ in page = 0 }
                Spacer()
                if let diff {
                    Text("\(diff.total) byte(s) would change on write")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(diff.total == 0 ? Color.secondary : Color.orange)
                }
                Button {
                    copyDump()
                } label: { Label("Copy dump", systemImage: "doc.on.doc") }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()

            if let diff, diff.total > 0 {
                HStack(spacing: 12) {
                    ForEach(Array(diff.sections.enumerated()), id: \.offset) { _, entry in
                        if entry.changed > 0 {
                            Text("\(entry.title): \(entry.changed)")
                                .font(.caption2.monospacedDigit())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                Divider()
            }

            if model.baseImage == nil {
                Spacer()
                Text("Read the radio or open an image to inspect its memory.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, row in
                            Text(line(address: row.address, bytes: row.bytes))
                                .font(.system(size: 11.5, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                Divider()
                HStack {
                    Button { page = max(0, page - 1) } label: {
                        Label("Previous", systemImage: "chevron.up")
                    }
                    .disabled(page <= 0)
                    Button { page = min(pageCount - 1, page + 1) } label: {
                        Label("Next", systemImage: "chevron.down")
                    }
                    .disabled(page >= pageCount - 1)
                    Spacer()
                    Text("page \(page + 1) of \(pageCount) · \(sectionLines.count) lines · 0x\(String(section.bounds.start, radix: 16).uppercased())–0x\(String(section.bounds.end - 1, radix: 16).uppercased())")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    private func line(address: Int, bytes: [UInt8]) -> String {
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        let ascii = bytes.map { $0 >= 32 && $0 < 127 ? String(UnicodeScalar($0)) : "." }.joined()
        return String(format: "%04X  ", address)
            + hex.padding(toLength: 47, withPad: " ", startingAt: 0)
            + "  " + ascii
    }

    private func copyDump() {
        let text = sectionLines.map { line(address: $0.address, bytes: $0.bytes) }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        model.status = "Copied \(sectionLines.count) dump line(s) to the clipboard."
    }
}

struct LogPane: View {
    @ObservedObject var model: ForgeModel

    var body: some View {
        VStack(spacing: 0) {
            PaneHeading(title: "Link log",
                        subtitle: "Everything the Bluetooth session did, in order. Useful when a read stalls.")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.link.log.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            Divider()
            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.link.log.joined(separator: "\n"), forType: .string)
                } label: { Label("Copy log", systemImage: "doc.on.doc") }
                Spacer()
                Text("\(model.link.log.count) entries").font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }
}

struct WriteSheet: View {
    @ObservedObject var model: ForgeModel
    let preview: WritePreview
    @State private var acknowledged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Write to the radio").font(.title3.bold())
            if let busy = model.busy {
                VStack(alignment: .leading, spacing: 8) {
                    Text(busy).font(.headline)
                    ProgressView(value: model.progress)
                    Text(model.progressNote).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                Text("\(preview.diff.total) byte(s) will change across \(preview.blockCount) blocks of 128 bytes. The app reads the whole radio back afterwards and compares it byte for byte.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                GroupBox("What changes") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(preview.diff.sections.enumerated()), id: \.offset) { _, entry in
                            HStack {
                                Text(entry.title)
                                Spacer()
                                Text("\(entry.changed) byte(s)")
                                    .monospacedDigit()
                                    .foregroundStyle(entry.changed == 0 ? .secondary : .primary)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(6)
                }

                if model.backup == nil {
                    Label("No backup saved yet — the app keeps the pre-write image in memory and the radio itself is unaffected until the last block lands.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label("Backup captured. You can restore it from File ▸ Open image if this goes sideways.",
                          systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Toggle("The radio is on, near the Mac, and I am fine overwriting its channel list and settings.", isOn: $acknowledged)
                    .font(.callout)

                Spacer()

                HStack {
                    Button("Cancel") { model.writePreview = nil }
                    Spacer()
                    Button("Write and verify") {
                        model.commitWrite()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!acknowledged)
                }
            }
        }
        .padding(20)
        .frame(width: 520, height: model.busy == nil ? 430 : 200)
    }
}
