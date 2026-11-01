// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 duderayuh
//
// Mini5 Forge — radio image container, region map and byte obfuscation.
// Layout derived from public reverse-engineering of the Baofeng MINI-5
// (service 0xFFE0 / characteristic 0xFFE1 BLE programming protocol).

import Foundation

public enum RadioLayout {
    /// Concatenated size of all CPS-known regions.
    public static let imageSize = 0x8240           // 33,344
    public static let trailer = "UV-5R Mini"       // 10-byte trailer on raw .img files
    public static let channelSlots = 1000           // slot 1000 is reserved / unsupported
    public static let usableChannels = 999
    public static let channelSize = 32

    public struct Region {
        public let address: Int
        public let size: Int
        public let offset: Int
    }

    public static let regions: [Region] = [
        Region(address: 0x0000, size: 0x8040, offset: 0),        // channels + gap
        Region(address: 0x9000, size: 0x0040, offset: 0x8040),   // general settings
        Region(address: 0xA000, size: 0x01C0, offset: 0x8080),   // DTMF
    ]

    public static let channelRegionEnd = 0x8040
    public static let vfoA = 0x8000
    public static let vfoB = 0x8020
    public static let settings = 0x9000
    public static let dtmf = 0xA000
    public static let wirelessCPSFlag = 0x9022   // must stay 1 or the radio drops BLE programming

    public enum Section: Int, CaseIterable, Identifiable {
        case channels, gap, vfo, settings, dtmf
        public var id: Int { rawValue }
        public var title: String {
            switch self {
            case .channels: return "Channel records"
            case .gap: return "Unmapped gap"
            case .vfo: return "VFO A / B"
            case .settings: return "General settings"
            case .dtmf: return "DTMF"
            }
        }
        public var bounds: (start: Int, end: Int) {
            switch self {
            case .channels: return (0x0000, 0x7D00)
            case .gap: return (0x7D00, 0x8000)
            case .vfo: return (0x8000, 0x8040)
            case .settings: return (0x9000, 0x9040)
            case .dtmf: return (0xA000, 0xA1C0)
            }
        }
    }

    /// IPv4-style address -> offset in the concatenated image.
    public static func offset(forAddress address: Int) -> Int? {
        for r in regions where address >= r.address && address < r.address + r.size {
            return r.offset + (address - r.address)
        }
        return nil
    }

    public static func address(forOffset offset: Int) -> Int? {
        for r in regions where offset >= r.offset && offset < r.offset + r.size {
            return r.address + (offset - r.offset)
        }
        return nil
    }

    /// Involutive byte transform the radio applies over the whole CPS image.
    public static func crypt(_ value: UInt8, at index: Int) -> UInt8 {
        let key: [UInt8] = [0x43, 0x4F, 0x20, 0x37]     // 'C', 'O', ' ', '7'
        let k = key[index % 4]
        guard k != 0x20 else { return value }
        if value == 0 || value == 0xFF || value == k || value == (k ^ 0xFF) { return value }
        return value ^ k
    }
}

/// A CPS image held in *decoded* (plain) form; every index is the image offset.
public struct RadioImage: Equatable {
    public var bytes: [UInt8]

    public init() {
        bytes = [UInt8](repeating: 0xFF, count: RadioLayout.imageSize)
    }

    /// Build from the raw (obfuscated) bytes the radio sends.
    public init(wire: [UInt8]) {
        bytes = wire.enumerated().map { RadioLayout.crypt($1, at: $0) }
    }

    /// Raw bytes for the wire or a .img file.
    public var wireBytes: [UInt8] {
        bytes.enumerated().map { RadioLayout.crypt($1, at: $0) }
    }

    public subscript(offset: Int) -> UInt8 {
        get { bytes[offset] }
        set { bytes[offset] = newValue }
    }

    public func byte(at address: Int) -> UInt8? {
        guard let o = RadioLayout.offset(forAddress: address) else { return nil }
        return bytes[o]
    }

    public mutating func setByte(_ value: UInt8, at address: Int) {
        guard let o = RadioLayout.offset(forAddress: address) else { return }
        bytes[o] = value
    }

    public func slice(from address: Int, count: Int) -> [UInt8]? {
        guard let o = RadioLayout.offset(forAddress: address), o + count <= bytes.count else { return nil }
        return Array(bytes[o..<(o + count)])
    }

    public mutating func write(_ payload: [UInt8], to address: Int) {
        guard let o = RadioLayout.offset(forAddress: address) else { return }
        for (i, b) in payload.enumerated() where o + i < bytes.count {
            bytes[o + i] = b
        }
    }

    // MARK: file interop

    /// Ham-Rx / Mini 5 Studio raw image: 33,344 bytes plus a 10-byte trailer.
    public var fileData: Data { Data(wireBytes + Array(RadioLayout.trailer.utf8)) }

    public init?(fileData data: Data) {
        let raw = [UInt8](data)
        if raw.count == RadioLayout.imageSize + 10 {
            let tail = String(decoding: raw[RadioLayout.imageSize...], as: UTF8.self)
            guard tail == RadioLayout.trailer else { return nil }
            self.init(wire: Array(raw[0..<RadioLayout.imageSize]))
        } else if raw.count == RadioLayout.imageSize {
            self.init(wire: raw)
        } else {
            return nil
        }
    }

    public static let empty = RadioImage()
}

/// Byte/character codecs for radio fields.
public enum FieldCodec {
    public static let gbk: String.Encoding = {
        let cf = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String.Encoding(rawValue: cf)
    }()

    /// Channel names / DTMF group names are GBK, 0xFF-terminated.
    public static func decodeName(_ bytes: ArraySlice<UInt8>) -> String {
        var slice = Array(bytes)
        if let end = slice.firstIndex(of: 0xFF) { slice = Array(slice[..<end]) }
        if slice.isEmpty { return "" }
        return String(data: Data(slice), encoding: gbk)
            ?? String(decoding: slice, as: UTF8.self).trimmingCharacters(in: .controlCharacters)
    }

    public static func encodeName(_ text: String, maxBytes: Int) -> [UInt8]? {
        guard let data = text.data(using: gbk) else { return nil }
        let bytes = [UInt8](data)
        if bytes.count > maxBytes { return nil }
        return bytes
    }

    /// "146.52000" -> 4 BCD bytes, little-endian pair order.
    public static func encodeFrequency(_ text: String) -> [UInt8]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 3, parts[1].count == 5 else { return nil }
        let digits = String(parts[0]) + String(parts[1])
        guard digits.count == 8, digits.allSatisfy({ $0.isNumber }), let n = Int(digits) else { return nil }
        var value = n
        var out = [UInt8]()
        for _ in 0..<4 {
            let pair = value % 100
            value /= 100
            out.append(UInt8((pair / 10) * 16 + pair % 10))
        }
        return out
    }

    public static func decodeFrequency(_ bytes: ArraySlice<UInt8>) -> String? {
        let b = Array(bytes)
        guard b.count == 4 else { return nil }
        if b.allSatisfy({ $0 == 0xFF }) { return nil }
        var digits = ""
        for i in (0..<4).reversed() {
            let hi = b[i] >> 4, lo = b[i] & 0x0F
            guard hi <= 9, lo <= 9 else { return nil }
            digits += "\(hi)\(lo)"
        }
        guard digits.count == 8 else { return nil }
        let head = digits.prefix(3)
        let tail = digits.suffix(5)
        return "\(head).\(tail)"
    }

    /// VFO frequencies are stored as one decimal digit per byte.
    public static func encodeVFOFrequency(_ text: String) -> [UInt8]? {
        let digits = text.replacingOccurrences(of: ".", with: "")
        guard text.count == 9, digits.count == 8, digits.allSatisfy({ $0.isNumber }) else { return nil }
        return digits.map { UInt8(String($0))! }
    }

    public static func decodeVFOFrequency(_ bytes: [UInt8]) -> String? {
        guard bytes.count >= 8 else { return nil }
        if bytes[0] == 0xFF { return "400.12500" }
        var digits = ""
        for b in bytes[0..<8] { digits += "\(min(b, 9))" }
        let head = digits.prefix(3), tail = digits.suffix(5)
        return "\(head).\(tail)"
    }

    /// VFO offset is 7 digits: "005.0000".
    public static func encodeOffset(_ text: String) -> [UInt8]? {
        let digits = text.replacingOccurrences(of: ".", with: "")
        guard text.count == 8, digits.count == 7, digits.allSatisfy({ $0.isNumber }) else { return nil }
        return digits.map { UInt8(String($0))! }
    }

    public static func decodeOffset(_ bytes: [UInt8]) -> String {
        guard bytes.count >= 7 else { return "000.0000" }
        if bytes[0] == 0xFF { return "000.0000" }
        var digits = ""
        for b in bytes[0..<7] { digits += "\(min(b, 9))" }
        return "\(digits.prefix(3)).\(digits.suffix(4))"
    }

    /// DTMF digit nibbles: 0-9, A-D, *, #.
    public static let dtmfDigits = Array("0123456789ABCD*#")

    public static func encodeDTMF(_ text: String, maxDigits: Int) -> [UInt8]? {
        let upper = text.uppercased()
        guard upper.count <= maxDigits else { return nil }
        var out = [UInt8]()
        for ch in upper {
            guard let idx = dtmfDigits.firstIndex(of: ch) else { return nil }
            out.append(UInt8(idx))
        }
        return out
    }

    public static func decodeDTMF(_ bytes: ArraySlice<UInt8>) -> String {
        var out = ""
        for b in bytes {
            if b == 0xFF { break }
            out.append(dtmfDigits[Int(b % 16)])
        }
        return out
    }

    /// Normalise user input to the canonical "###.#####" form; returns nil if impossible.
    public static func padFrequency(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts[0].count == 3, parts[0].allSatisfy({ $0.isNumber }) else { return nil }
        var frac = parts.count == 2 ? String(parts[1]) : ""
        guard frac.allSatisfy({ $0.isNumber }) else { return nil }
        let integer = String(parts[0])
        if frac.count > 5 {
            // CHIRP exports six decimals (Hz). Drop or round the extra digit.
            let head = String(frac.prefix(5))
            let tail = frac.dropFirst(5)
            if tail.contains(where: { $0 != "0" }) {
                let value = (Double(trimmed) ?? 0) * 100000
                let rounded = (value).rounded() / 100000
                let text = String(format: "%.5f", rounded)
                return Double(text) != nil ? text : nil
            }
            frac = head
        }
        if frac.isEmpty { frac = "0" }
        return integer + "." + frac.padding(toLength: 5, withPad: "0", startingAt: 0)
    }
}
