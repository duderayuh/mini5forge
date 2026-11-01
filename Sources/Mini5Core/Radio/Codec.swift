// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 duderayuh
//
// Mini5 Forge — image <-> configuration codec and wire frame builder.

import Foundation

public enum Codec {

    // MARK: settings field map (CPS name, byte offset inside 0x9000 block, modulus)

    public static let functionFields: [(key: String, offset: Int, modulus: Int)] = [
        ("sql", 0, 10), ("saveMode", 1, 2), ("vox", 2, 10), ("backlight", 3, 9),
        ("dualStandby", 4, 2), ("tot", 5, 13), ("beep", 6, 2), ("voice", 7, 2),
        ("language", 8, 2), ("sideTone", 9, 4), ("scanMode", 10, 3),
        ("pttDly", 12, 256), ("chADisType", 13, 3), ("chBDisType", 14, 3),
        ("autoLock", 16, 2), ("alarmMode", 17, 3), ("alarmTone", 18, 2),
        ("tailClear", 20, 2), ("rptTailClear", 21, 11), ("rptTailDet", 22, 11),
        ("roger", 23, 2), ("fmEnable", 25, 2), ("powerOnDisType", 28, 3),
        ("tone", 29, 4), ("voxDlyTime", 32, 16), ("menuQuitTime", 33, 11),
        ("totAlarm", 40, 11), ("ctsDcsScanType", 43, 3), ("key2Short", 50, 256),
        ("rstMenu", 55, 256), ("voxSw", 58, 2),
        ("chAWorkmode", 26, 2), ("chBWorkmode", 27, 2), ("keyLock", 27, 2),
    ]

    /// Grouped for the UI, in a sensible order.
    public static let settingsGroups: [(title: String, keys: [String])] = [
        ("Display & keys", ["backlight", "powerOnDisType", "language", "voice", "beep", "autoLock",
                            "keyLock", "menuQuitTime", "key2Short", "rstMenu"]),
        ("Receiver", ["sql", "saveMode", "dualStandby", "scanMode", "voxSw", "vox", "voxDlyTime",
                      "fmEnable", "sqMode"]),
        ("Transmit", ["tot", "totAlarm", "pttDly", "sideTone", "tone", "tailClear", "rptTailClear",
                      "rptTailDet", "roger"]),
        ("Channel displays", ["chADisType", "chBDisType", "chAWorkmode", "chBWorkmode"]),
        ("Tones & alarm", ["alarmMode", "alarmTone", "ctsDcsScanType"]),
    ]

    // MARK: decode

    public static func channels(from image: RadioImage) -> [Channel] {
        (0..<RadioLayout.channelSlots).map { index in
            decodeChannel(image.bytes[(index * 32)..<(index * 32 + 32)], slot: index + 1)
        }
    }

    public static func decodeChannel(_ bytes: ArraySlice<UInt8>, slot: Int) -> Channel {
        var channel = Channel(slot: slot)
        let b = Array(bytes)
        guard let rx = FieldCodec.decodeFrequency(b[0..<4]) else { return channel }
        channel.rxFreq = rx
        channel.txFreq = FieldCodec.decodeFrequency(b[4..<8]) ?? ""
        channel.rxTone = ToneTable.label(lo: b[8], hi: b[9])
        channel.txTone = ToneTable.label(lo: b[10], hi: b[11])
        channel.signalGroup = Int(b[12]) % 20
        channel.pttid = Int(b[13]) % 4
        channel.txPower = Int(b[14]) % 2
        channel.bandwide = Int((b[15] >> 6) & 1)
        channel.sqMode = Int((b[15] >> 4) & 1)
        channel.busyLock = Int((b[15] >> 3) & 1)
        channel.scanAdd = Int((b[15] >> 2) & 1)
        channel.fhss = Int(b[15] & 1)
        channel.name = FieldCodec.decodeName(b[20..<32])
        return channel
    }

    public static func settings(from image: RadioImage) -> RadioSettings {
        let s = Array(image.bytes[0x8040..<0x8080])
        var values: [String: Int] = [:]
        for f in functionFields where f.key != "chAWorkmode" && f.key != "chBWorkmode" && f.key != "keyLock" {
            values[f.key] = Int(s[f.offset]) % f.modulus
        }
        values["chAWorkmode"] = Int(s[26] & 0x0F) % 2
        values["chBWorkmode"] = Int((s[26] >> 4) & 0x0F) % 2
        values["keyLock"] = Int(s[27] & 1)
        values["pTTdelay_raw"] = nil
        return RadioSettings(values: values)
    }

    public static func shared(from image: RadioImage) -> VFOShared {
        let s = Array(image.bytes[0x8040..<0x8080])
        var shared = VFOShared()
        shared.optTid = Int(s[11])
        shared.busyLock = Int(s[15]) % 2
        let low = Int(s[44]) + Int(s[45]) * 256
        let high = Int(s[46]) + Int(s[47]) * 256
        shared.scanLow = low > 1000 ? 400 : low
        shared.scanHigh = high > 1000 ? 520 : high
        return shared
    }

    public static func dtmf(from image: RadioImage) -> DTMFConfig {
        var config = DTMFConfig()
        let s = Array(image.bytes[0x8040..<0x8080])
        let d = Array(image.bytes[0x8080..<0x8240])
        config.localID = FieldCodec.decodeDTMF(d[0..<3])
        config.wordTime = Int(d[7]) % 6
        config.idleTime = Int(d[8]) % 6
        config.separator = Int(d[9]) % 6
        config.groupCall = Int(d[10]) % 7
        config.hangUp = Int(s[57]) % 8
        for i in 0..<20 {
            let base = 32 + i * 16
            config.groups[i] = FieldCodec.decodeDTMF(d[base..<(base + 3)])
            config.groupNames[i] = FieldCodec.decodeName(d[(base + 5)..<(base + 15)])
        }
        config.onlineCode = FieldCodec.decodeDTMF(d[384..<400])
        config.offlineCode = FieldCodec.decodeDTMF(d[400..<416])
        return config
    }

    public static func vfo(from image: RadioImage, side: String) -> VFOSettings {
        let base = side == "A" ? 0x8000 : 0x8020
        let b = Array(image.bytes[base..<(base + 32)])
        var vfo = VFOSettings(freq: "400.12500", rxTone: "OFF", txTone: "OFF", busyLock: 0,
                              dir: 0, signalGroup: 0, txPower: 0, bandwide: 0, fhss: 0,
                              step: 0, sqMode: 0, offset: "000.0000")
        vfo.freq = FieldCodec.decodeVFOFrequency(b) ?? "400.12500"
        vfo.rxTone = ToneTable.label(lo: b[8], hi: b[9])
        vfo.txTone = ToneTable.label(lo: b[10], hi: b[11])
        vfo.busyLock = Int(b[13]) % 2
        vfo.dir = Int((b[14] >> 4) & 3)
        vfo.signalGroup = side == "A" ? Int(b[14]) : Int(b[14] & 0x0F)
        vfo.txPower = Int(b[16])
        vfo.bandwide = Int((b[17] >> 6) & 1)
        vfo.fhss = Int(b[17] & 1)
        vfo.step = Int(b[19])
        vfo.sqMode = Int(b[27])
        vfo.offset = FieldCodec.decodeOffset(Array(b[20..<27]))
        return vfo
    }

    public static func config(from image: RadioImage) -> RadioConfig {
        RadioConfig(channels: channels(from: image),
                    settings: settings(from: image),
                    vfoA: vfo(from: image, side: "A"),
                    vfoB: vfo(from: image, side: "B"),
                    vfoShared: shared(from: image),
                    dtmf: dtmf(from: image))
    }

    // MARK: encode

    public static func encodeChannel(_ channel: Channel) -> [UInt8] {
        var b = [UInt8](repeating: 0xFF, count: 32)
        guard !channel.rxFreq.isEmpty, let rx = FieldCodec.encodeFrequency(channel.rxFreq) else { return b }
        b.replaceSubrange(0..<4, with: rx)
        if let tx = FieldCodec.encodeFrequency(channel.txFreq) { b.replaceSubrange(4..<8, with: tx) }
        if let tone = ToneTable.bytes(for: channel.rxTone) {
            b[8] = tone.0; b[9] = tone.1
        }
        if let tone = ToneTable.bytes(for: channel.txTone) {
            b[10] = tone.0; b[11] = tone.1
        }
        b[12] = UInt8(clamping: channel.signalGroup)
        b[13] = UInt8(clamping: channel.pttid)
        b[14] = UInt8(clamping: channel.txPower)
        b[15] = UInt8(((channel.bandwide & 1) << 6) | ((channel.sqMode & 1) << 4)
                      | ((channel.busyLock & 1) << 3) | ((channel.scanAdd & 1) << 2) | (channel.fhss & 1))
        if let name = FieldCodec.encodeName(channel.name, maxBytes: 12) {
            b.replaceSubrange(20..<(20 + name.count), with: name)
        }
        return b
    }

    public static func encodeSettingsBlock(_ settings: RadioSettings, shared: VFOShared, hangUp: Int) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 64)
        for f in functionFields where f.key != "chAWorkmode" && f.key != "chBWorkmode" && f.key != "keyLock" {
            b[f.offset] = UInt8(clamping: settings[f.key])
        }
        b[11] = UInt8(clamping: shared.optTid)
        b[15] = UInt8(clamping: shared.busyLock)
        b[26] = UInt8((settings["chAWorkmode"] & 1) | ((settings["chBWorkmode"] & 1) << 4))
        b[27] = UInt8(settings["keyLock"] & 1)
        b[57] = UInt8(clamping: hangUp)
        let low = UInt16(clamping: shared.scanLow), high = UInt16(clamping: shared.scanHigh)
        b[44] = UInt8(low & 0xFF); b[45] = UInt8(low >> 8)
        b[46] = UInt8(high & 0xFF); b[47] = UInt8(high >> 8)
        b[0x22] = 1     // keep Bluetooth programming enabled
        return b
    }

    public static func encodeVFOBlock(_ vfo: VFOSettings, side: String, aOffset: String) -> [UInt8] {
        var b = [UInt8](repeating: 0xFF, count: 32)
        if let digits = FieldCodec.encodeVFOFrequency(vfo.freq) { b.replaceSubrange(0..<8, with: digits) }
        if let tone = ToneTable.bytes(for: vfo.rxTone) { b[8] = tone.0; b[9] = tone.1 }
        if let tone = ToneTable.bytes(for: vfo.txTone) { b[10] = tone.0; b[11] = tone.1 }
        b[13] = UInt8(clamping: vfo.busyLock)
        b[14] = UInt8(((vfo.dir & 3) << 4) | (vfo.signalGroup & 0x0F))
        b[15] = 0
        b[16] = UInt8(clamping: vfo.txPower)
        b[17] = UInt8(((vfo.bandwide & 1) << 6) | (vfo.fhss & 1))
        b[18] = 0
        b[19] = UInt8(clamping: vfo.step)
        if let digits = FieldCodec.encodeOffset(vfo.offset) {
            b.replaceSubrange(20..<27, with: digits)
            // Factory CPS quirk: VFO B takes its final offset digit from VFO A.
            if side == "B", let a = FieldCodec.encodeOffset(aOffset) { b[26] = a[6] }
        }
        b[27] = UInt8(clamping: vfo.sqMode)
        return b
    }

    public static func encodeDTMFBlock(_ config: DTMFConfig) -> [UInt8] {
        var b = [UInt8](repeating: 0xFF, count: 448)
        func put(_ text: String, _ offset: Int, _ maxDigits: Int) -> Bool {
            guard let digits = FieldCodec.encodeDTMF(text, maxDigits: maxDigits) else { return false }
            for (i, d) in digits.enumerated() { b[offset + i] = d }
            return true
        }
        _ = put(config.localID, 0, 3)
        b[7] = UInt8(clamping: config.wordTime)
        b[8] = UInt8(clamping: config.idleTime)
        b[9] = UInt8(clamping: config.separator)
        b[10] = UInt8(clamping: config.groupCall)
        for i in 0..<20 {
            let base = 32 + i * 16
            _ = put(config.groups[i], base, 3)
            if let name = FieldCodec.encodeName(config.groupNames[i], maxBytes: 10) {
                b.replaceSubrange((base + 5)..<(base + 5 + name.count), with: name)
            }
        }
        _ = put(config.onlineCode, 384, 16)
        _ = put(config.offlineCode, 400, 16)
        return b
    }

    // MARK: apply configuration to an image

    /// Write the configuration into a copy of `base`, reproducing the factory layout.
    public static func apply(_ config: RadioConfig, to base: RadioImage) -> RadioImage {
        var image = base
        for (index, channel) in config.channels.enumerated() where index < RadioLayout.channelSlots {
            image.write(encodeChannel(channel), to: index * 32)
        }
        // Factory CPS mirrors the final 64-byte channel buffer across the trailing gap,
        // alternating a transformed copy with the plain copy.
        let finalPair = Array(image.bytes[0x7CC0..<0x7D00])
        let transformed = finalPair.enumerated().map { RadioLayout.crypt($1, at: 0x7CC0 + $0) }
        for i in 0..<12 {
            image.write(i % 2 == 0 ? transformed : finalPair, to: 0x7D00 + i * 64)
        }
        image.write(encodeVFOBlock(config.vfoA, side: "A", aOffset: config.vfoA.offset), to: RadioLayout.vfoA)
        image.write(encodeVFOBlock(config.vfoB, side: "B", aOffset: config.vfoA.offset), to: RadioLayout.vfoB)
        image.write(encodeSettingsBlock(config.settings, shared: config.vfoShared, hangUp: config.dtmf.hangUp),
                    to: RadioLayout.settings)
        image.write(encodeDTMFBlock(config.dtmf), to: RadioLayout.dtmf)
        image.setByte(1, at: RadioLayout.wirelessCPSFlag)
        return image
    }

    public static func image(for config: RadioConfig) -> RadioImage {
        apply(config, to: RadioImage())
    }

    // MARK: wire frames

    public static let writeRegions: [(address: Int, size: Int)] = [
        (0x0000, 0x8040), (0x9000, 0x0040), (0xA000, 0x01C0),
    ]

    public static func readAddresses() -> [Int] {
        RadioLayout.regions.flatMap { region in
            stride(from: region.address, to: region.address + region.size, by: 64).map { $0 }
        }
    }

    public static let writeBlockSize = 128

    /// 132-byte write frames: [0x57, addr hi, addr lo, 128, 128 payload bytes].
    public static func writeFrames(for image: RadioImage) -> [[UInt8]] {
        var frames: [[UInt8]] = []
        for region in writeRegions {
            let blocks = (region.size + writeBlockSize - 1) / writeBlockSize
            for i in 0..<blocks {
                let address = region.address + i * writeBlockSize
                var payload = [UInt8](repeating: 0xFF, count: writeBlockSize)
                let usable = min(writeBlockSize, region.address + region.size - address)
                for j in 0..<usable {
                    if let offset = RadioLayout.offset(forAddress: address + j) {
                        payload[j] = RadioLayout.crypt(image.bytes[offset], at: offset)
                    }
                }
                frames.append([0x57, UInt8((address >> 8) & 0xFF), UInt8(address & 0xFF),
                               UInt8(writeBlockSize)] + payload)
            }
        }
        return frames
    }

    public static func writeAddresses() -> [Int] {
        writeRegions.flatMap { region in
            let blocks = (region.size + writeBlockSize - 1) / writeBlockSize
            return (0..<blocks).map { region.address + $0 * writeBlockSize }
        }
    }
}

// MARK: - Diffing

public struct ImageDiff {
    public var total: Int
    public var sections: [(title: String, changed: Int)]
    public var offsets: [Int]
}

public extension RadioImage {
    static func diff(_ a: RadioImage, _ b: RadioImage) -> ImageDiff {
        var offsets: [Int] = []
        for i in 0..<min(a.bytes.count, b.bytes.count) where a.bytes[i] != b.bytes[i] {
            offsets.append(i)
        }
        let sections: [(String, Int)] = RadioLayout.Section.allCases.map { section in
            let bounds = section.bounds
            let from = RadioLayout.offset(forAddress: bounds.start) ?? 0
            let to = (RadioLayout.offset(forAddress: bounds.end - 1) ?? 0) + 1
            let changed = offsets.filter { $0 >= from && $0 < to }.count
            return (section.title, changed)
        }
        return ImageDiff(total: offsets.count, sections: sections, offsets: offsets)
    }
}
