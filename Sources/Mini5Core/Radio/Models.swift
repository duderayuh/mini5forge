// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 duderayuh
//
// Mini5 Forge — editable models mirroring the CPS data structures.

import Foundation

public struct Channel: Identifiable, Equatable, Hashable {
    public var slot: Int              // 1-based position in the radio
    public var rxFreq: String = ""    // "##.#####" MHz, empty = vacant
    public var txFreq: String = ""    // empty = receive only
    public var rxTone: String = "OFF"
    public var txTone: String = "OFF"
    public var name: String = ""
    public var txPower: Int = 0       // 0 high, 1 low
    public var bandwide: Int = 0      // 0 wide, 1 narrow
    public var scanAdd: Int = 0
    public var busyLock: Int = 0
    public var sqMode: Int = 0
    public var pttid: Int = 0
    public var signalGroup: Int = 0
    public var fhss: Int = 0

    public var id: Int { slot }
    public var isVacant: Bool { rxFreq.isEmpty }

    public init(slot: Int, rxFreq: String = "", txFreq: String = "", rxTone: String = "OFF",
                txTone: String = "OFF", name: String = "", txPower: Int = 0, bandwide: Int = 0,
                scanAdd: Int = 0, busyLock: Int = 0, sqMode: Int = 0, pttid: Int = 0,
                signalGroup: Int = 0, fhss: Int = 0) {
        self.slot = slot
        self.rxFreq = rxFreq
        self.txFreq = txFreq
        self.rxTone = rxTone
        self.txTone = txTone
        self.name = name
        self.txPower = txPower
        self.bandwide = bandwide
        self.scanAdd = scanAdd
        self.busyLock = busyLock
        self.sqMode = sqMode
        self.pttid = pttid
        self.signalGroup = signalGroup
        self.fhss = fhss
    }

    public init(slot: Int) { self.slot = slot }

    public var displayName: String { name.isEmpty ? "—" : name }

    public var offsetDescription: String {
        guard !rxFreq.isEmpty else { return "" }
        if txFreq.isEmpty { return "TX off" }
        if txFreq == rxFreq { return "simplex" }
        guard let r = Double(rxFreq), let t = Double(txFreq) else { return "" }
        let delta = t - r
        return String(format: "%+.4f MHz", delta)
    }
}

public struct VFOSettings: Equatable {
    public var freq: String
    public var rxTone: String
    public var txTone: String
    public var busyLock: Int
    public var dir: Int
    public var signalGroup: Int
    public var txPower: Int
    public var bandwide: Int
    public var fhss: Int
    public var step: Int
    public var sqMode: Int
    public var offset: String
}

public struct VFOShared: Equatable {
    public var optTid: Int = 0
    public var busyLock: Int = 0
    public var scanLow: Int = 136
    public var scanHigh: Int = 174
}

public struct DTMFConfig: Equatable {
    public var localID: String = ""
    public var groups: [String] = Array(repeating: "", count: 20)
    public var groupNames: [String] = Array(repeating: "", count: 20)
    public var wordTime: Int = 0
    public var idleTime: Int = 0
    public var separator: Int = 0
    public var groupCall: Int = 0
    public var hangUp: Int = 0
    public var onlineCode: String = ""
    public var offlineCode: String = ""
}

public struct RadioSettings: Equatable {
    /// Function settings keyed by CPS name (values are validated against Options.function).
    public var values: [String: Int]

    public subscript(key: String) -> Int {
        get { values[key] ?? 0 }
        set { values[key] = newValue }
    }
}

/// A complete editable configuration: channels + settings + VFOs + DTMF.
public struct RadioConfig: Equatable {
    public var channels: [Channel]
    public var settings: RadioSettings
    public var vfoA: VFOSettings
    public var vfoB: VFOSettings
    public var vfoShared: VFOShared
    public var dtmf: DTMFConfig

    public init(channels: [Channel], settings: RadioSettings, vfoA: VFOSettings,
                vfoB: VFOSettings, vfoShared: VFOShared, dtmf: DTMFConfig) {
        self.channels = channels
        self.settings = settings
        self.vfoA = vfoA
        self.vfoB = vfoB
        self.vfoShared = vfoShared
        self.dtmf = dtmf
    }

    public var populatedChannels: [Channel] { channels.filter { !$0.isVacant } }

    public var nextVacantSlot: Int? { channels.first(where: { $0.isVacant })?.slot }
}
