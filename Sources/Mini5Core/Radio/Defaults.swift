// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 duderayuh
//
// Factory defaults for the MINI-5 (used for brand-new documents and demo mode).

import Foundation

public enum Defaults {
    public static let function: [String: Int] = ["alarmMode": 0, "alarmTone": 1, "autoLock": 0, "backlight": 3, "beep": 1, "chADisType": 0, "chAWorkmode": 0, "chBDisType": 0, "chBWorkmode": 0, "ctsDcsScanType": 0, "dualStandby": 1, "fmEnable": 0, "key2Short": 28, "keyLock": 0, "language": 0, "menuQuitTime": 0, "powerOnDisType": 0, "pttDly": 5, "roger": 0, "rptTailClear": 5, "rptTailDet": 5, "rstMenu": 1, "saveMode": 1, "scanMode": 1, "sideTone": 0, "sql": 3, "tailClear": 1, "tone": 2, "tot": 8, "totAlarm": 0, "voice": 1, "vox": 4, "voxDlyTime": 6, "voxSw": 0]

    public static let vfoA = VFOSettings(freq: "146.52000", rxTone: "OFF", txTone: "OFF", busyLock: 0, dir: 0, signalGroup: 0, txPower: 0, bandwide: 0, fhss: 0, step: 1, sqMode: 0, offset: "000.0000")
    public static let vfoB = VFOSettings(freq: "446.00000", rxTone: "OFF", txTone: "OFF", busyLock: 0, dir: 0, signalGroup: 0, txPower: 0, bandwide: 0, fhss: 0, step: 1, sqMode: 0, offset: "000.0000")

    public static let vfoShared = VFOShared(optTid: 0, busyLock: 0,
                                            scanLow: 136, scanHigh: 174)

    public static let dtmf = DTMFConfig(localID: "",
                                        groups: ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""],
                                        groupNames: ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""],
                                        wordTime: 1, idleTime: 1,
                                        separator: 4, groupCall: 6,
                                        hangUp: 1, onlineCode: "",
                                        offlineCode: "")

    public static var config: RadioConfig {
        RadioConfig(channels: (1...RadioLayout.channelSlots).map { Channel(slot: $0) },
                    settings: RadioSettings(values: function),
                    vfoA: vfoA, vfoB: vfoB, vfoShared: vfoShared, dtmf: dtmf)
    }
}
