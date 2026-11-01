// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 duderayuh
//
// Mini5 Forge — CSV channel import/export.

import Foundation

public enum ChannelCSV {

    public struct ImportResult {
        public var channels: [Channel]
        public var warnings: [String]
    }

    static func splitLine(_ line: String, separator: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        var lookahead: Character?
        while true {
            let ch: Character?
            if let l = lookahead { ch = l; lookahead = nil } else { ch = iterator.next() }
            guard let ch else { break }
            if ch == "\"" {
                if inQuotes {
                    if let next = iterator.next() {
                        if next == "\"" { current.append("\"") } else { inQuotes = false; lookahead = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if ch == separator && !inQuotes {
                fields.append(current); current = ""
            } else {
                current.append(ch)
            }
        }
        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func detectSeparator(_ line: String) -> Character {
        let candidates: [Character] = [",", ";", "\t"]
        let scored = candidates.map { c in (c, line.filter { $0 == c }.count) }
        return scored.max { $0.1 < $1.1 }?.0 ?? ","
    }

    public static func parse(_ text: String) -> ImportResult {
        var warnings: [String] = []
        let rawLines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerLine = rawLines.first else {
            return ImportResult(channels: [], warnings: ["File is empty."])
        }
        let separator = detectSeparator(headerLine)
        let headers = splitLine(headerLine, separator: separator).map {
            $0.lowercased().replacingOccurrences(of: " ", with: "_")
        }

        func column(_ aliases: [String]) -> Int? {
            for alias in aliases {
                if let index = headers.firstIndex(of: alias) { return index }
            }
            return nil
        }
        let nameCol = column(["name", "call", "callsign", "channel_name", "label", "alpha_tag"])
        let rxCol = column(["rx", "rx_freq", "rx_frequency", "frequency", "receive", "receive_frequency", "freq"])
        let txCol = column(["tx", "tx_freq", "tx_frequency", "transmit", "transmit_frequency",
                            "input", "input_freq", "input_frequency", "rptr_input", "uplink"])
        let offsetCol = column(["offset", "shift", "duplex_offset"])
        let duplexCol = column(["duplex", "shift_direction"])
        // RepeaterBook puts the downlink (receive) tone in TSQL and the uplink (transmit) tone in PL.
        let rToneCol = column(["rx_tone", "r_tone", "rtone", "tone_rx", "ctcss_rx", "r_ctcss", "rx_ctcss",
                               "rtonefreq", "tsql", "rx_pl"])
        let tToneCol = column(["tx_tone", "t_tone", "ttone", "tone_tx", "ctcss_tx", "t_ctcss", "tx_ctcss",
                               "ctonefreq", "pl", "tx_pl"])
        let dcsCol = column(["dtcscode", "dtcs_code", "dcs", "dtcs"])
        let toneModeCol = column(["tone", "tonemode", "tone_mode"])
        let genericToneCol = column(["tone", "ctcss", "tsql", "pl"])
        let modeCol = column(["mode", "modulation"])
        let powerCol = column(["power", "txpower", "tx_power", "watt"])
        let bwCol = column(["bandwidth", "bw", "wide", "narrow"])
        let scanCol = column(["scan", "scanskip", "lockout"])

        guard rxCol != nil else {
            return ImportResult(channels: [], warnings: ["No receive-frequency column found. Expected a header such as RX, Frequency, or Rx Freq."])
        }

        func field(_ cols: [Int], _ row: [String]) -> String? {
            for index in cols where index >= 0 {
                guard index < row.count else { continue }
                let value = row[index].trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
            return nil
        }
        func tone(_ value: String?) -> String? {
            guard var value, !value.isEmpty else { return nil }
            value = value.uppercased()
            if value == "OFF" || value == "NONE" || value == "0" || value == "-" { return "OFF" }
            if value.hasPrefix("D") { return value.replacingOccurrences(of: " ", with: "") }
            if let hz = Double(value) {
                let label = hz < 1000 ? String(format: "%.1f", hz) : String(format: "%.1f", hz / 10)
                if ToneTable.all.contains(where: { $0 == label }) { return label }
                let alt = String(format: "%.1f", hz)
                if ToneTable.all.contains(where: { $0 == alt }) { return alt }
            }
            return ToneTable.all.first(where: { $0.caseInsensitiveCompare(value) == .orderedSame })
        }

        var channels: [Channel] = []
        for (rowIndex, line) in rawLines.dropFirst().enumerated() {
            let row = splitLine(line, separator: separator)
            guard !row.isEmpty else { continue }
            guard let rawRx = field([rxCol!], row), !rawRx.isEmpty else { continue }
            if let modeCol, let mode = field([modeCol], row)?.uppercased(),
               !mode.isEmpty, !mode.hasPrefix("FM"), !mode.hasPrefix("NFM") {
                warnings.append("Row \(rowIndex + 1): skipped non-FM mode \(mode).")
                continue
            }
            guard var rx = FieldCodec.padFrequency(rawRx) else {
                warnings.append("Row \(rowIndex + 1): unreadable receive frequency “\(rawRx)”.")
                continue
            }
            if !rx.contains(".") { rx = FieldCodec.padFrequency(rawRx) ?? rx }
            guard let rxValue = Double(rx), (100.0...999.99999).contains(rxValue) else {
                warnings.append("Row \(rowIndex + 1): receive frequency \(rawRx) outside 100–999.99999 MHz.")
                continue
            }

            var tx = ""
            if let rawTx = field(txCol.map { [$0] } ?? [], row), let padded = FieldCodec.padFrequency(rawTx) {
                tx = padded
            } else if let rawOffset = field(offsetCol.map { [$0] } ?? [], row),
                      let offset = Double(rawOffset.replacingOccurrences(of: "+", with: "")) {
                var signed = offset
                if let duplex = field(duplexCol.map { [$0] } ?? [], row)?.uppercased() {
                    if duplex.hasPrefix("-") { signed = -abs(offset) }
                    if duplex.hasPrefix("+") { signed = abs(offset) }
                }
                if abs(signed) > 0, let padded = FieldCodec.padFrequency(String(format: "%.5f", rxValue + signed)) {
                    tx = padded
                }
            }
            if tx.isEmpty { tx = "" }

            var channel = Channel(slot: channels.count + 1, rxFreq: rx, txFreq: tx, name: "")
            if let nameCol, let rawName = field([nameCol], row) {
                channel.name = String(rawName.prefix(12))
            }
            // CHIRP writes a Tone *mode* next to rToneFreq/cToneFreq; RepeaterBook writes raw values
            // in PL (uplink) and TSQL (downlink). Detect which layout this is, then resolve tones.
            let chirpStyle = (rToneCol.map { headers[$0] } == "rtonefreq")
                || (tToneCol.map { headers[$0] } == "ctonefreq")
            if chirpStyle {
                let mode = (field([toneModeCol ?? -1], row) ?? "").uppercased()
                let dcs = tone(field([dcsCol ?? -1], row)) ?? "OFF"
                let rxValue = tone(field([rToneCol ?? -1], row)) ?? "OFF"
                let txValue = tone(field([tToneCol ?? -1], row)) ?? rxValue
                switch mode {
                case "TSQL", "TSQL-REV":
                    channel.rxTone = rxValue; channel.txTone = rxValue
                case "TONE":
                    channel.rxTone = "OFF"; channel.txTone = txValue
                case "DTCS", "DTCS-REV", "DTCS REV":
                    channel.rxTone = dcs; channel.txTone = dcs
                case "CROSS":
                    channel.rxTone = rxValue; channel.txTone = txValue
                default:
                    channel.rxTone = "OFF"; channel.txTone = "OFF"
                }
            } else {
                let generic = tone(field([genericToneCol ?? -1], row))
                channel.rxTone = tone(field([rToneCol ?? -1], row)) ?? generic ?? "OFF"
                channel.txTone = tone(field([tToneCol ?? -1], row)) ?? generic ?? "OFF"
            }
            if let powerCol, let rawPower = field([powerCol], row)?.uppercased() {
                channel.txPower = rawPower.hasPrefix("L") || rawPower == "1" ? 1 : 0
            }
            if let bwCol, let rawBW = field([bwCol], row)?.uppercased() {
                channel.bandwide = rawBW.hasPrefix("N") || rawBW == "1" ? 1 : 0
            }
            channel.scanAdd = 1
            if let scanCol, let rawScan = field([scanCol], row)?.uppercased() {
                if rawScan.hasPrefix("S") || rawScan == "0" || rawScan == "LOCKOUT" { channel.scanAdd = 0 }
            }
            if FieldCodec.encodeName(channel.name, maxBytes: 12) == nil {
                warnings.append("Row \(rowIndex + 1): name has characters the radio cannot store; trimmed.")
                channel.name = String(channel.name.unicodeScalars.filter { $0.isASCII }.prefix(12))
            }
            channels.append(channel)
        }
        if channels.isEmpty { warnings.append("No usable channels in that file.") }
        return ImportResult(channels: channels, warnings: warnings)
    }

    public static func export(_ channels: [Channel]) -> String {
        var lines = ["Channel,Name,RX,TX,RX_Tone,TX_Tone,Power,Bandwidth,Scan,Group"]
        for channel in channels where !channel.isVacant {
            let fields = [String(channel.slot), channel.name, channel.rxFreq, channel.txFreq,
                          channel.rxTone, channel.txTone, channel.txPower == 0 ? "High" : "Low",
                          channel.bandwide == 0 ? "Wide" : "Narrow",
                          channel.scanAdd == 1 ? "Include" : "Skip", String(channel.signalGroup + 1)]
            lines.append(fields.map { value -> String in
                value.contains(",") ? "\"" + value + "\"" : value
            }.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
