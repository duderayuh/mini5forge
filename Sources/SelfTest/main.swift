// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 duderayuh
//
// Byte-exact cross-check of the Swift codec against reference protocol captures.

import Foundation


func bytes(fromHex hex: String) -> [UInt8] {
    var out: [UInt8] = []
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        out.append(UInt8(hex[index..<next], radix: 16)!)
        index = next
    }
    return out
}

func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

func fail(_ message: String) -> Never {
    print("FAIL: \(message)")
    exit(1)
}

guard CommandLine.arguments.count > 1 else {
    print("usage: mini5forge-selftest <golden.json>")
    exit(2)
}
let path = CommandLine.arguments[1]
guard let data = FileManager.default.contents(atPath: path),
      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    fail("cannot read golden file at \(path)")
}
guard let input = root["input"] as? [String: Any],
      let channelDicts = input["channels"] as? [[String: Any]],
      let vfoDict = input["vfos"] as? [String: Any],
      let funDict = input["funCfgs"] as? [String: Any],
      let dtmfDict = input["dtmfs"] as? [String: Any] else {
    fail("golden file missing input blocks")
}

func int(_ d: [String: Any], _ k: String, _ fallback: Int = 0) -> Int {
    if let v = d[k] as? Int { return v }
    if let v = d[k] as? Double { return Int(v) }
    if let v = d[k] as? String, let n = Int(v) { return n }
    return fallback
}
func str(_ d: [String: Any], _ k: String, _ fallback: String = "") -> String {
    (d[k] as? String) ?? fallback
}

var channels: [Channel] = []
for (i, d) in channelDicts.enumerated() {
    var c = Channel(slot: i + 1)
    c.rxFreq = str(d, "rxFreq")
    c.txFreq = str(d, "txFreq")
    c.rxTone = str(d, "strRxCtsDcs", "OFF")
    c.txTone = str(d, "strTxCtsDcs", "OFF")
    c.name = str(d, "name")
    c.txPower = int(d, "txPower")
    c.bandwide = int(d, "bandwide")
    c.scanAdd = int(d, "scanAdd")
    c.busyLock = int(d, "busyLock")
    c.sqMode = int(d, "sqMode")
    c.pttid = int(d, "pttid")
    c.signalGroup = int(d, "signalGroup")
    c.fhss = int(d, "fhss")
    channels.append(c)
}

var settings: [String: Int] = [:]
for (k, v) in funDict where !k.hasPrefix("$") {
    if let n = v as? Int { settings[k] = n }
}

var vfoA = VFOSettings(freq: "146.52000", rxTone: "OFF", txTone: "OFF", busyLock: 0, dir: 0,
                       signalGroup: 0, txPower: 0, bandwide: 0, fhss: 0, step: 0, sqMode: 0,
                       offset: "000.0000")
var vfoB = vfoA
func loadVFO(_ v: inout VFOSettings, _ side: String) {
    let p = "vfo" + side
    v.freq = str(vfoDict, p + "Freq", "400.12500")
    v.rxTone = str(vfoDict, "strVFO\(side)RxCtsDcs", "OFF")
    v.txTone = str(vfoDict, "strVFO\(side)TxCtsDcs", "OFF")
    v.busyLock = int(vfoDict, side == "A" ? "vfoABusylock" : "vfoBBusyLock")
    v.dir = int(vfoDict, p + "Dir")
    v.signalGroup = int(vfoDict, p + "SignalGroup")
    v.txPower = int(vfoDict, p + "TxPower")
    v.bandwide = int(vfoDict, p + "Bandwide")
    v.fhss = int(vfoDict, p + "Fhss")
    v.step = int(vfoDict, p + "Step")
    v.sqMode = int(vfoDict, p + "SQMode")
    v.offset = str(vfoDict, p + "Offset", "000.0000")
}
loadVFO(&vfoA, "A")
loadVFO(&vfoB, "B")
let shared = VFOShared(optTid: int(vfoDict, "vfopttid"),
                       busyLock: int(vfoDict, "busyLock"),
                       scanLow: Int(str(vfoDict, "vfoScanRang_L", "136")) ?? 136,
                       scanHigh: Int(str(vfoDict, "vfoScanRang_H", "174")) ?? 174)

var dtmf = DTMFConfig()
dtmf.localID = str(dtmfDict, "localID")
dtmf.groups = (dtmfDict["group"] as? [String]) ?? dtmf.groups
dtmf.groupNames = (dtmfDict["groupName"] as? [String]) ?? dtmf.groupNames
dtmf.wordTime = int(dtmfDict, "wordTime")
dtmf.idleTime = int(dtmfDict, "idleTime")
dtmf.separator = int(dtmfDict, "separator")
dtmf.groupCall = int(dtmfDict, "groupCall")
dtmf.hangUp = int(dtmfDict, "hangUp")
dtmf.onlineCode = str(dtmfDict, "onlineCode")
dtmf.offlineCode = str(dtmfDict, "offlineCode")

let config = RadioConfig(channels: channels, settings: RadioSettings(values: settings),
                         vfoA: vfoA, vfoB: vfoB, vfoShared: shared, dtmf: dtmf)

var failures = 0
func check(_ ok: Bool, _ label: String, _ detail: @autoclosure () -> String = "") {
    if ok {
        print("  ok   \(label)")
    } else {
        failures += 1
        print("  FAIL \(label) \(detail())")
    }
}

print("== encode ==")
let image = Codec.image(for: config)
let wire = image.wireBytes
let expectedTarget = bytes(fromHex: root["target"] as! String)
check(wire.count == RadioLayout.imageSize, "image size \(wire.count)")
let targetMatches = wire == expectedTarget
var targetDetail = ""
if !targetMatches {
    let diffs = zip(wire, expectedTarget).enumerated().filter { $0.element.0 != $0.element.1 }
    targetDetail = "\(diffs.count) differing bytes, first at offset "
        + (diffs.first.map { String($0.offset, radix: 16) } ?? "-")
}
check(targetMatches, "image bytes match reference", targetDetail)

let frames = Codec.writeFrames(for: image)
let expectedFrames = (root["frames"] as! [String]).map(bytes(fromHex:))
check(frames.count == expectedFrames.count, "write frame count \(frames.count) == \(expectedFrames.count)")
if frames.count == expectedFrames.count {
    var mismatched = 0
    for (i, (a, b)) in zip(frames, expectedFrames).enumerated() where a != b {
        if mismatched == 0 { print("    first frame mismatch at index \(i)") }
        mismatched += 1
    }
    check(mismatched == 0, "all write frames byte-identical", "\(mismatched) mismatched")
}

print("== decode ==")
let roundTrip = Codec.config(from: image)
check(roundTrip.channels[0].rxFreq == "146.52000", "ch1 rx \(roundTrip.channels[0].rxFreq)")
check(roundTrip.channels[0].name == "CALLING", "ch1 name \(roundTrip.channels[0].name)")
check(roundTrip.channels[0].txTone == "100.0", "ch1 tx tone \(roundTrip.channels[0].txTone)")
check(roundTrip.channels[1].txFreq == "448.90000", "ch2 tx \(roundTrip.channels[1].txFreq)")
check(roundTrip.channels[2].rxTone == "D023N", "ch3 DCS \(roundTrip.channels[2].rxTone)")
check(roundTrip.channels[4].name == "测试频道", "ch5 GBK name \(roundTrip.channels[4].name)")
check(roundTrip.channels[5].isVacant, "ch6 vacant")
check(roundTrip.settings["sql"] == 5, "sql \(roundTrip.settings["sql"])")
check(roundTrip.vfoA.freq == "147.39000", "VFO A freq \(roundTrip.vfoA.freq)")
check(roundTrip.vfoB.freq == "446.10000", "VFO B freq \(roundTrip.vfoB.freq)")
check(roundTrip.dtmf.groupNames[3] == "GROUP3", "DTMF group name \(roundTrip.dtmf.groupNames[3])")
check(roundTrip.dtmf.offlineCode == "9#8*7", "DTMF offline code \(roundTrip.dtmf.offlineCode)")

print("== stability ==")
let second = Codec.image(for: roundTrip)
let stable = second.wireBytes == image.wireBytes
if !stable {
    let diffs = zip(second.wireBytes, image.wireBytes).enumerated().filter { $0.element.0 != $0.element.1 }
    print("  round-trip diffs: \(diffs.count)")
    for d in diffs.prefix(12) {
        let addr = RadioLayout.address(forOffset: d.offset).map { String($0, radix: 16) } ?? "?"
        print("    offset 0x\(String(d.offset, radix: 16)) addr 0x\(addr) expected \(String(d.element.1, radix: 16)) got \(String(d.element.0, radix: 16))")
    }
}
check(stable, "decode/encode round trip is byte-stable")

print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
