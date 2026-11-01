// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 duderayuh
//
// Mini5 Forge — application state and radio operations.

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CoreBluetooth

public enum Pane: String, CaseIterable, Identifiable {
    case channels, settings, vfo, dtmf, inspect, log
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .channels: return "Channels"
        case .settings: return "Settings"
        case .vfo: return "VFO"
        case .dtmf: return "DTMF"
        case .inspect: return "Inspect"
        case .log: return "Log"
        }
    }
    public var symbol: String {
        switch self {
        case .channels: return "list.number"
        case .settings: return "slider.horizontal.3"
        case .vfo: return "dot.radiowaves.left.and.right"
        case .dtmf: return "waveform"
        case .inspect: return "square.grid.3x3"
        case .log: return "text.alignleft"
        }
    }
}

public struct ForgeAlert: Identifiable {
    public let id = UUID()
    public var title: String
    public var message: String
}

public struct WritePreview: Identifiable {
    public let id = UUID()
    public var plan: RadioImage
    public var diff: ImageDiff
    public var blockCount: Int
}

@MainActor
public final class ForgeModel: ObservableObject {

    @Published public var link = RadioLink()
    @Published public private(set) var config: RadioConfig?
    @Published public private(set) var baseImage: RadioImage?
    @Published public private(set) var backup: (image: RadioImage, date: Date)?
    @Published public private(set) var sourceLabel = "Nothing loaded"
    @Published public var status = "Scan, pick your MINI-5, then read it."
    @Published public private(set) var busy: String?
    @Published public private(set) var progress: Double = 0
    @Published public var alert: ForgeAlert?
    @Published public var pane: Pane = .channels
    @Published public var dirty = false
    @Published public var searchText = ""
    @Published public var selectedSlot: Int?
    @Published public var writePreview: WritePreview?
    @Published public var lastVerified = false

    public init() {}

    public var hasDocument: Bool { config != nil }
    public var canRead: Bool { link.isConnected && busy == nil }
    public var canWrite: Bool { link.isConnected && busy == nil && config != nil && dirty }

    // MARK: - document lifecycle

    public func newDocument() {
        var fresh = Defaults.config
        fresh.channels = Array(fresh.channels.prefix(RadioLayout.usableChannels))
        config = fresh
        baseImage = Codec.image(for: fresh)
        sourceLabel = "New document (factory defaults)"
        dirty = false
        lastVerified = false
        status = "Started a fresh document from factory defaults. Read a radio first if you want to keep its settings."
    }

    public func openImage() {
        let panel = NSOpenPanel()
        panel.title = "Open a MINI-5 image"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            guard let data = try? Data(contentsOf: url), let image = RadioImage(fileData: data) else {
                alert = ForgeAlert(title: "Not a MINI-5 image",
                                   message: "Expected 33,344 bytes of CPS data (optionally with the UV-5R Mini trailer). That file is \(url.lastPathComponent).")
                return
            }
            load(image: image, label: url.lastPathComponent)
        }
    }

    public func load(image: RadioImage, label: String) {
        var loaded = Codec.config(from: image)
        loaded.channels = Array(loaded.channels.prefix(RadioLayout.usableChannels))
        config = loaded
        baseImage = image
        sourceLabel = label
        dirty = false
        lastVerified = false
        status = "Loaded \(label) — \(loaded.populatedChannels.count) programmed channels."
    }

    public func saveImage() {
        guard let image = writeCandidate() else { return }
        let panel = NSSavePanel()
        panel.title = "Save MINI-5 image"
        panel.nameFieldStringValue = defaultFileName()
        panel.allowedContentTypes = [UTType(filenameExtension: "img") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try image.fileData.write(to: url)
            status = "Saved \(url.lastPathComponent) (\(RadioLayout.imageSize) bytes of CPS data)."
        } catch {
            alert = ForgeAlert(title: "Could not save", message: error.localizedDescription)
        }
    }

    public func saveBackup() {
        guard let image = baseImage else {
            alert = ForgeAlert(title: "No image to back up", message: "Read the radio first.")
            return
        }
        backup = (image, Date())
        let panel = NSSavePanel()
        panel.title = "Save pre-flight backup"
        panel.nameFieldStringValue = "MINI5-backup-" + Self.stampFormatter.string(from: Date()) + ".img"
        panel.allowedContentTypes = [UTType(filenameExtension: "img") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try image.fileData.write(to: url)
            status = "Backup written to \(url.lastPathComponent). Keep it — it is the way back."
        } catch {
            alert = ForgeAlert(title: "Could not save backup", message: error.localizedDescription)
        }
    }

    private func defaultFileName() -> String {
        "MINI5-" + Self.stampFormatter.string(from: Date()) + ".img"
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f
    }()

    // MARK: - radio operations

    public func readRadio() {
        guard link.isConnected else {
            alert = ForgeAlert(title: "Not connected", message: "Connect to the radio first (Connect ▸ pick your MINI-5).")
            return
        }
        if dirty {
            alert = ForgeAlert(title: "Unsaved edits",
                               message: "You have edits that were not written to the radio. Reading now will replace them. Save the image first if you want to keep them.")
            return
        }
        run(title: "Reading radio") {
            let image = try await self.link.readAll { done, total in
                self.progress = Double(done) / Double(total)
                self.progressNote = "block \(done) of \(total)"
            }
            self.load(image: image, label: "Read from radio " + Self.stampFormatter.string(from: Date()))
            self.status = "Read \(RadioLayout.imageSize) bytes from the radio."
        }
    }

    @Published public var progressNote = ""

    private func run(title: String, _ work: @escaping () async throws -> Void) {
        busy = title
        progress = 0
        progressNote = ""
        Task {
            do {
                try await work()
            } catch {
                self.progressNote = ""
                self.busy = nil
                self.alert = ForgeAlert(title: title + " failed", message: error.localizedDescription)
                self.status = title + " failed: " + error.localizedDescription
                return
            }
            self.progressNote = ""
            self.busy = nil
        }
    }

    /// Build the image that would be written for the current configuration.
    public func writeCandidate() -> RadioImage? {
        guard let config else { return nil }
        return Codec.apply(config, to: baseImage ?? RadioImage())
    }

    public func prepareWrite() {
        guard let config, let base = baseImage else {
            alert = ForgeAlert(title: "Nothing to write", message: "Read the radio or open an image first.")
            return
        }
        guard !config.populatedChannels.isEmpty else {
            alert = ForgeAlert(title: "No channels", message: "At least one channel has to be programmed before writing.")
            return
        }
        if let problem = firstValidationProblem(config) {
            alert = ForgeAlert(title: "Fix this first", message: problem)
            return
        }
        guard link.isConnected else {
            alert = ForgeAlert(title: "Not connected", message: "Connect to the radio before writing.")
            return
        }
        let plan = Codec.apply(config, to: base)
        let diff = RadioImage.diff(base, plan)
        writePreview = WritePreview(plan: plan, diff: diff, blockCount: Codec.writeFrames(for: plan).count)
    }

    public func commitWrite() {
        guard let preview = writePreview else { return }
        if backup == nil, let base = baseImage {
            backup = (base, Date())
        }
        run(title: "Writing radio") {
            let frames = Codec.writeFrames(for: preview.plan).count
            let readback = try await self.link.writeAll(preview.plan) { done, total in
                self.progress = Double(done) / Double(total)
                self.progressNote = "block \(done) of \(total)"
            }
            let diff = RadioImage.diff(preview.plan, readback)
            self.baseImage = readback
            var updated = Codec.config(from: readback)
            updated.channels = Array(updated.channels.prefix(RadioLayout.usableChannels))
            self.config = updated
            self.dirty = false
            self.lastVerified = diff.total == 0
            if diff.total == 0 {
                self.status = "Wrote \(frames) blocks and verified every byte on read-back."
            } else {
                self.status = "Wrote \(frames) blocks; \(diff.total) byte(s) differ on read-back."
                self.alert = ForgeAlert(title: "Read-back mismatch",
                                        message: "\(diff.total) bytes differ from the intended image. The radio may have accepted the write with different normalisation, or the link glitched. Your backup is intact — save the image and compare before writing again.")
            }
            self.writePreview = nil
        }
    }

    public func wipeChannels() {
        guard var config else { return }
        config.channels = (1...RadioLayout.usableChannels).map { Channel(slot: $0) }
        self.config = config
        dirty = true
        status = "All channels cleared in the editor. The radio is untouched until you write."
    }

    // MARK: - editing

    public func updateChannel(_ channel: Channel) {
        guard var config, channel.slot >= 1, channel.slot <= config.channels.count else { return }
        config.channels[channel.slot - 1] = channel
        self.config = config
        dirty = true
    }

    public func markDirty() { dirty = true }

    public func replaceChannels(_ channels: [Channel]) {
        guard var config else { return }
        var updated = Array(channels.prefix(RadioLayout.usableChannels))
        while updated.count < RadioLayout.usableChannels {
            updated.append(Channel(slot: updated.count + 1))
        }
        config.channels = updated
        self.config = config
        dirty = true
    }

    public func setSetting(_ key: String, _ value: Int) {
        config?.settings[key] = value
        dirty = true
    }

    public func setVFO(_ side: String, _ path: WritableKeyPath<VFOSettings, String>, _ value: String) {
        guard var config else { return }
        if side == "A" { config.vfoA[keyPath: path] = value } else { config.vfoB[keyPath: path] = value }
        self.config = config
        dirty = true
    }

    public func setVFO(_ side: String, _ path: WritableKeyPath<VFOSettings, Int>, _ value: Int) {
        guard var config else { return }
        if side == "A" { config.vfoA[keyPath: path] = value } else { config.vfoB[keyPath: path] = value }
        self.config = config
        dirty = true
    }

    public func setShared(_ path: WritableKeyPath<VFOShared, Int>, _ value: Int) {
        guard var config else { return }
        config.vfoShared[keyPath: path] = value
        self.config = config
        dirty = true
    }

    public func setDTMF(_ mutate: (inout DTMFConfig) -> Void) {
        guard var config else { return }
        mutate(&config.dtmf)
        self.config = config
        dirty = true
    }

    // MARK: - CSV

    public func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText, .text, .tabSeparatedText]
        panel.allowsMultipleSelection = false
        panel.title = "Import channels from CSV"
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let result = ChannelCSV.parse(text)
        guard !result.channels.isEmpty else {
            alert = ForgeAlert(title: "Nothing imported", message: result.warnings.joined(separator: "\n"))
            return
        }
        guard var config else {
            alert = ForgeAlert(title: "No document", message: "Read the radio or start a new document before importing.")
            return
        }
        let limit = min(result.channels.count, RadioLayout.usableChannels)
        for (index, channel) in result.channels.prefix(limit).enumerated() {
            var copy = channel
            copy.slot = index + 1
            config.channels[index] = copy
        }
        for index in limit..<config.channels.count {
            config.channels[index] = Channel(slot: index + 1)
        }
        self.config = config
        dirty = true
        status = "Imported \(limit) channel(s) from \(url.lastPathComponent)."
        if !result.warnings.isEmpty {
            alert = ForgeAlert(title: "Imported with notes", message: result.warnings.prefix(20).joined(separator: "\n"))
        }
    }

    public func exportCSV() {
        guard let config else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MINI5-channels.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ChannelCSV.export(config.channels).write(to: url, atomically: true, encoding: .utf8)
            status = "Exported \(config.populatedChannels.count) channel(s) to \(url.lastPathComponent)."
        } catch {
            alert = ForgeAlert(title: "Export failed", message: error.localizedDescription)
        }
    }

    // MARK: - validation

    public func firstValidationProblem(_ config: RadioConfig) -> String? {
        if config.populatedChannels.isEmpty { return "Program at least one channel." }
        for channel in config.populatedChannels {
            guard let rxFreq = Double(channel.rxFreq) else { return "Channel \(channel.slot): receive frequency is not a number." }
            if rxFreq < 100 || rxFreq > 999.99999 { return "Channel \(channel.slot): receive frequency must be 100.00000–999.99999 MHz." }
            if !channel.txFreq.isEmpty {
                guard let txFreq = Double(channel.txFreq) else { return "Channel \(channel.slot): transmit frequency is not a number." }
                if txFreq < 100 || txFreq > 999.99999 { return "Channel \(channel.slot): transmit frequency must be 100.00000–999.99999 MHz." }
            }
            if ToneTable.bytes(for: channel.rxTone) == nil { return "Channel \(channel.slot): unknown receive tone “\(channel.rxTone)”." }
            if ToneTable.bytes(for: channel.txTone) == nil { return "Channel \(channel.slot): unknown transmit tone “\(channel.txTone)”." }
            if FieldCodec.encodeName(channel.name, maxBytes: 12) == nil { return "Channel \(channel.slot): name is too long or has characters the radio cannot store." }
        }
        if FieldCodec.encodeVFOFrequency(config.vfoA.freq) == nil { return "VFO A frequency must look like 146.52000." }
        if FieldCodec.encodeVFOFrequency(config.vfoB.freq) == nil { return "VFO B frequency must look like 446.00000." }
        if FieldCodec.encodeName(config.dtmf.localID, maxBytes: 3) == nil, config.dtmf.localID.count > 3 {
            return "DTMF ID is at most 3 digits."
        }
        return nil
    }
}
