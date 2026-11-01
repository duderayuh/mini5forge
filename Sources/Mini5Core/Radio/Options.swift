// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 duderayuh
//
// Generated dropdown labels for radio settings (stored value -> human label).
import Foundation

public enum Options {
    public static let function: [String: [(Int, String)]] = [
        "sql": [(0, "0"), (1, "1"), (2, "2"), (3, "3"), (4, "4"), (5, "5")],
        "saveMode": [(0, "Off"), (1, "On")],
        "vox": [(0, "1"), (1, "2"), (2, "3"), (3, "4"), (4, "5"), (5, "6"), (6, "7"), (7, "8"), (8, "9")],
        "voxSw": [(0, "Off"), (1, "On")],
        "voxDlyTime": [(0, "0.5s"), (1, "0.6s"), (2, "0.7s"), (3, "0.8s"), (4, "0.9s"), (5, "1.0s"), (6, "1.1s"), (7, "1.2s"), (8, "1.3s"), (9, "1.4s"), (10, "1.5s"), (11, "1.6s"), (12, "1.7s"), (13, "1.8s"), (14, "1.9s"), (15, "2.0s")],
        "dualStandby": [(0, "Off"), (1, "On")],
        "tot": [(0, "Off"), (1, "15s"), (2, "30s"), (3, "45s"), (4, "60s"), (5, "75s"), (6, "90s"), (7, "105s"), (8, "120s"), (9, "135s"), (10, "150s"), (11, "165s"), (12, "180s")],
        "beep": [(0, "Off"), (1, "On")],
        "sideTone": [(0, "Off"), (1, "Keypad tones"), (2, "ID tones"), (3, "Keypad and ID tones")],
        "scanMode": [(0, "Time-based resume"), (1, "Resume when signal ends"), (2, "Stop when a signal is found")],
        "pttDly": [(0, "100 ms"), (1, "200 ms"), (2, "300 ms"), (3, "400 ms"), (4, "500 ms"), (5, "600 ms"), (6, "700 ms"), (7, "800 ms"), (8, "900 ms"), (9, "1100 ms"), (10, "1200 ms"), (11, "1300 ms"), (12, "1400 ms"), (13, "1500 ms"), (14, "1600 ms"), (15, "1700 ms"), (16, "1800 ms"), (17, "1900 ms"), (18, "2000 ms"), (19, "2100 ms"), (20, "2200 ms"), (21, "2300 ms"), (22, "2400 ms"), (23, "2500 ms"), (24, "2600 ms"), (25, "2700 ms"), (26, "2800 ms"), (27, "2900 ms"), (28, "3000 ms")],
        "chADisType": [(0, "Name"), (1, "Frequency"), (2, "Channel number")],
        "chBDisType": [(0, "Name"), (1, "Frequency"), (2, "Channel number")],
        "autoLock": [(0, "Off"), (1, "On")],
        "voice": [(0, "Off"), (1, "On")],
        "alarmMode": [(0, "Local alarm"), (1, "Transmit alarm sound"), (2, "Transmit alarm code")],
        "alarmTone": [(0, "Off"), (1, "On")],
        "tailClear": [(0, "Off"), (1, "On")],
        "rptTailClear": [(0, "0 ms"), (1, "100 ms"), (2, "200 ms"), (3, "300 ms"), (4, "400 ms"), (5, "500 ms"), (6, "600 ms"), (7, "700 ms"), (8, "800 ms"), (9, "900 ms"), (10, "1000 ms")],
        "rptTailDet": [(0, "0 ms"), (1, "100 ms"), (2, "200 ms"), (3, "300 ms"), (4, "400 ms"), (5, "500 ms"), (6, "600 ms"), (7, "700 ms"), (8, "800 ms"), (9, "900 ms"), (10, "1000 ms")],
        "roger": [(0, "Off"), (1, "On")],
        "fmEnable": [(0, "Allowed"), (1, "Disabled")],
        "chAWorkmode": [(0, "Frequency mode"), (1, "Channel mode")],
        "chBWorkmode": [(0, "Frequency mode"), (1, "Channel mode")],
        "keyLock": [(0, "Off"), (1, "On")],
        "powerOnDisType": [(0, "LOGO"), (1, "Battery voltage")],
        "tone": [(0, "1000Hz"), (1, "1450Hz"), (2, "1750Hz"), (3, "2100Hz")],
        "backlight": [(0, "Always on"), (1, "5 s"), (2, "10 s"), (3, "15 s"), (4, "20 s")],
        "menuQuitTime": [(0, "5 s"), (1, "10 s"), (2, "15 s"), (3, "20 s"), (4, "25 s"), (5, "30 s"), (6, "35 s"), (7, "40 s"), (8, "45 s"), (9, "50 s"), (10, "60 s")],
        "language": [(0, "English"), (1, "Chinese")],
        "rstMenu": [(0, "Off"), (1, "On")],
        "totAlarm": [(0, "Off"), (1, "1s"), (2, "2s"), (3, "3s"), (4, "4s"), (5, "5s"), (6, "6s"), (7, "7s"), (8, "8s"), (9, "9s"), (10, "10s")],
        "ctsDcsScanType": [(0, "All"), (1, "Receive"), (2, "Transmit")],
        "key2Short": [(7, "FM broadcast radio"), (28, "Channel scan"), (29, "Frequency search"), (45, "VOX"), (8, "Flashlight"), (3, "Alarm")],
    ]

    public static let channel: [String: [(Int, String)]] = [
        "busyLock": [(0, "Off"), (1, "On")],
        "txPower": [(0, "High"), (1, "Low")],
        "bandwide": [(0, "Wide"), (1, "Narrow")],
        "scanAdd": [(0, "Skip"), (1, "Include")],
        "sqMode": [(0, "Off"), (1, "On")],
        "pttid": [(0, "Off"), (1, "At start of transmission"), (2, "At end of transmission"), (3, "At start and end")],
        "signalGroup": [(0, "1"), (1, "2"), (2, "3"), (3, "4"), (4, "5"), (5, "6"), (6, "7"), (7, "8"), (8, "9"), (9, "10"), (10, "11"), (11, "12"), (12, "13"), (13, "14"), (14, "15"), (15, "16"), (16, "17"), (17, "18"), (18, "19"), (19, "20")],
        "fhss": [(0, "Off"), (1, "On")],
    ]

    public static let vfo: [String: [(Int, String)]] = [
        "vfoADir": [(0, "Off"), (1, "Plus offset"), (2, "Minus offset")],
        "vfoASignalGroup": [(0, "1"), (1, "2"), (2, "3"), (3, "4"), (4, "5"), (5, "6"), (6, "7"), (7, "8"), (8, "9"), (9, "10"), (10, "11"), (11, "12"), (12, "13"), (13, "14"), (14, "15"), (15, "16"), (16, "17"), (17, "18"), (18, "19"), (19, "20")],
        "vfoATxPower": [(0, "High"), (1, "Low")],
        "vfoABandwide": [(0, "Wide"), (1, "Narrow")],
        "vfoASQMode": [(0, "QT/DQT"), (1, "QT/DQT*DTMF"), (2, "QT/DQT+DTMF")],
        "vfoAStep": [(0, "2.5  KHz"), (1, "5.0  KHz"), (2, "6.25 KHz"), (3, "10.0 KHz"), (4, "12.5 KHz"), (5, "20.0 KHz"), (6, "25.0 KHz"), (7, "50.0 KHz")],
        "vfoAFhss": [(0, "Off"), (1, "On")],
        "vfoBDir": [(0, "Off"), (1, "Plus offset"), (2, "Minus offset")],
        "vfoBSignalGroup": [(0, "1"), (1, "2"), (2, "3"), (3, "4"), (4, "5"), (5, "6"), (6, "7"), (7, "8"), (8, "9"), (9, "10"), (10, "11"), (11, "12"), (12, "13"), (13, "14"), (14, "15"), (15, "16"), (16, "17"), (17, "18"), (18, "19"), (19, "20")],
        "vfoBTxPower": [(0, "High"), (1, "Low")],
        "vfoBBandwide": [(0, "Wide"), (1, "Narrow")],
        "vfoBSQMode": [(0, "QT/DQT"), (1, "QT/DQT*DTMF"), (2, "QT/DQT+DTMF")],
        "vfoBStep": [(0, "2.5  KHz"), (1, "5.0  KHz"), (2, "6.25 KHz"), (3, "10.0 KHz"), (4, "12.5 KHz"), (5, "20.0 KHz"), (6, "25.0 KHz"), (7, "50.0 KHz")],
        "vfoBFhss": [(0, "Off"), (1, "On")],
        "busyLock": [(0, "Off"), (1, "On")],
        "vfopttid": [(0, "Off"), (1, "At start of transmission"), (2, "At end of transmission"), (3, "At start and end")],
    ]

    public static let dtmf: [String: [(Int, String)]] = [
        "wordTime": [(0, "50ms"), (1, "100ms"), (2, "200ms"), (3, "300ms"), (4, "400ms"), (5, "500ms")],
        "idleTime": [(0, "50ms"), (1, "100ms"), (2, "200ms"), (3, "300ms"), (4, "400ms"), (5, "500ms")],
        "hangUp": [(0, "3s"), (1, "4s"), (2, "5s"), (3, "6s"), (4, "7s"), (5, "8s"), (6, "9s"), (7, "10s")],
        "separator": [(0, "A"), (1, "B"), (2, "C"), (3, "D"), (4, "*"), (5, "#")],
        "groupCall": [(0, "OFF"), (1, "A"), (2, "B"), (3, "C"), (4, "D"), (5, "*"), (6, "#")],
    ]

    public static func label(_ table: [String: [(Int, String)]], _ key: String, _ value: Int) -> String {
        if let hit = table[key]?.first(where: { $0.0 == value }) { return hit.1 }
        return "\(value)"
    }
}
