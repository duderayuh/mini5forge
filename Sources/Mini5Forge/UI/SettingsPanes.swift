// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 duderayuh
//
// Mini5 Forge — settings, VFO and DTMF editors.

import SwiftUI

enum SettingLabel {
    static let names: [String: String] = [
        "sql": "Squelch", "saveMode": "Battery saving", "voxSw": "Voice-activated transmit",
        "vox": "VOX sensitivity", "voxDlyTime": "VOX release delay", "dualStandby": "Dual watch",
        "tot": "Transmit time limit", "beep": "Keypad beep", "sideTone": "Side tone",
        "scanMode": "Scan resume behaviour", "pttDly": "PTT ID delay",
        "chADisType": "Upper display shows", "chBDisType": "Lower display shows",
        "autoLock": "Automatic keypad lock", "voice": "Spoken prompts", "alarmMode": "Alarm mode",
        "alarmTone": "Alarm sound", "tailClear": "Squelch tail suppression",
        "rptTailClear": "Repeater tail suppression", "rptTailDet": "Repeater tail delay",
        "roger": "End-of-transmission beep", "fmEnable": "FM broadcast receiver",
        "chAWorkmode": "Upper display mode", "chBWorkmode": "Lower display mode",
        "keyLock": "Keypad lock", "powerOnDisType": "Startup display",
        "tone": "Repeater access tone", "backlight": "Screen backlight",
        "menuQuitTime": "Menu exit delay", "language": "Prompt language", "rstMenu": "Reset menu",
        "totAlarm": "Transmit timeout warning", "ctsDcsScanType": "Tone scan mode",
        "key2Short": "Side-key short press",
    ]
    static func name(_ key: String) -> String { names[key] ?? key }
}

struct SettingRow: View {
    @ObservedObject var model: ForgeModel
    let key: String

    private var modulus: Int {
        Codec.functionFields.first(where: { $0.key == key })?.modulus ?? 256
    }

    var body: some View {
        let value = Binding<Int>(
            get: { model.config?.settings[key] ?? 0 },
            set: { model.setSetting(key, $0) })
        if let options = Options.function[key], !options.isEmpty {
            Picker(SettingLabel.name(key), selection: value) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
        } else {
            HStack {
                Text(SettingLabel.name(key))
                Spacer()
                Stepper(value: value, in: 0...max(1, modulus - 1)) {
                    Text("\(value.wrappedValue)")
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }
}

struct SettingsPane: View {
    @ObservedObject var model: ForgeModel

    var body: some View {
        VStack(spacing: 0) {
            PaneHeading(title: "Radio settings",
                        subtitle: "The 0x9000 block. Values come straight from the radio; nothing is normalised or invented.")
            Divider()
            Form {
                ForEach(Array(Codec.settingsGroups.enumerated()), id: \.offset) { _, group in
                    Section(group.title) {
                        ForEach(group.keys.filter { $0 != "sqMode" }, id: \.self) { key in
                            SettingRow(model: model, key: key)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct VFOPane: View {
    @ObservedObject var model: ForgeModel

    var body: some View {
        VStack(spacing: 0) {
            PaneHeading(title: "VFO A and B",
                        subtitle: "The frequency-mode registers the radio uses outside channel mode.")
            Divider()
            Form {
                if let config = model.config {
                    Section("VFO A") { vfoFields(side: "A", vfo: config.vfoA) }
                    Section("VFO B") { vfoFields(side: "B", vfo: config.vfoB) }
                    Section("Shared") {
                        Picker("PTT ID on VFO", selection: Binding(
                            get: { model.config?.vfoShared.optTid ?? 0 },
                            set: { model.setShared(\.optTid, $0) })) {
                            ForEach(Options.vfo["vfopttid"] ?? [], id: \.0) { Text($0.1).tag($0.0) }
                        }
                        Picker("Busy-channel lock", selection: Binding(
                            get: { model.config?.vfoShared.busyLock ?? 0 },
                            set: { model.setShared(\.busyLock, $0) })) {
                            Text("Off").tag(0); Text("On").tag(1)
                        }
                        HStack {
                            Text("VFO scan range")
                            Spacer()
                            TextField("low", value: Binding(
                                get: { model.config?.vfoShared.scanLow ?? 136 },
                                set: { model.setShared(\.scanLow, $0) }), format: .number)
                                .frame(width: 64)
                                .textFieldStyle(.roundedBorder)
                            Text("to").foregroundStyle(.secondary)
                            TextField("high", value: Binding(
                                get: { model.config?.vfoShared.scanHigh ?? 174 },
                                set: { model.setShared(\.scanHigh, $0) }), format: .number)
                                .frame(width: 64)
                                .textFieldStyle(.roundedBorder)
                            Text("MHz").foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Load an image first.").foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private func vfoFields(side: String, vfo: VFOSettings) -> some View {
        let current = (side == "A" ? model.config?.vfoA : model.config?.vfoB) ?? vfo
        HStack {
            Text("Frequency")
            Spacer()
            TextField("146.52000", text: Binding(
                get: { current.freq },
                set: { model.setVFO(side, \.freq, $0) }))
                .frame(width: 110)
                .textFieldStyle(.roundedBorder)
                .monospaced()
            Text("MHz").foregroundStyle(.secondary)
        }
        Picker("Receive tone", selection: Binding(
            get: { current.rxTone },
            set: { model.setVFO(side, \.rxTone, $0) })) {
            ForEach(ToneTable.all, id: \.self) { Text($0 == "OFF" ? "Off" : $0).tag($0) }
        }
        Picker("Transmit tone", selection: Binding(
            get: { current.txTone },
            set: { model.setVFO(side, \.txTone, $0) })) {
            ForEach(ToneTable.all, id: \.self) { Text($0 == "OFF" ? "Off" : $0).tag($0) }
        }
        Picker("Offset direction", selection: Binding(
            get: { current.dir },
            set: { model.setVFO(side, \.dir, $0) })) {
            ForEach(Options.vfo["vfo\(side)Dir"] ?? [], id: \.0) { Text($0.1).tag($0.0) }
        }
        HStack {
            Text("Offset")
            Spacer()
            TextField("005.0000", text: Binding(
                get: { current.offset },
                set: { model.setVFO(side, \.offset, $0) }))
                .frame(width: 100)
                .textFieldStyle(.roundedBorder)
                .monospaced()
            Text("MHz").foregroundStyle(.secondary)
        }
        Picker("Step", selection: Binding(
            get: { current.step },
            set: { model.setVFO(side, \.step, $0) })) {
            ForEach(Options.vfo["vfo\(side)Step"] ?? [], id: \.0) { Text($0.1).tag($0.0) }
        }
        Picker("Transmit power", selection: Binding(
            get: { current.txPower },
            set: { model.setVFO(side, \.txPower, $0) })) {
            Text("High").tag(0); Text("Low").tag(1)
        }
        Picker("Bandwidth", selection: Binding(
            get: { current.bandwide },
            set: { model.setVFO(side, \.bandwide, $0) })) {
            Text("Wide").tag(0); Text("Narrow").tag(1)
        }
        Picker("Squelch mode", selection: Binding(
            get: { current.sqMode },
            set: { model.setVFO(side, \.sqMode, $0) })) {
            ForEach(Options.vfo["vfo\(side)SQMode"] ?? [], id: \.0) { Text($0.1).tag($0.0) }
        }
        Picker("Busy-channel lock", selection: Binding(
            get: { current.busyLock },
            set: { model.setVFO(side, \.busyLock, $0) })) {
            Text("Off").tag(0); Text("On").tag(1)
        }
    }
}

struct DTMFPane: View {
    @ObservedObject var model: ForgeModel

    var body: some View {
        VStack(spacing: 0) {
            PaneHeading(title: "DTMF",
                        subtitle: "Own ID, 20 call groups, and the codes sent at the start and end of a transmission.")
            Divider()
            Form {
                if let config = model.config {
                    Section("Identity") {
                        HStack {
                            Text("Own ID")
                            Spacer()
                            TextField("3 digits", text: Binding(
                                get: { config.dtmf.localID },
                                set: { value in model.setDTMF { $0.localID = value } }))
                                .frame(width: 110)
                                .textFieldStyle(.roundedBorder)
                                .monospaced()
                        }
                        Picker("Tone duration", selection: Binding(
                            get: { config.dtmf.wordTime },
                            set: { value in model.setDTMF { $0.wordTime = value } })) {
                            ForEach(Options.dtmf["wordTime"] ?? [], id: \.0) { Text($0.1).tag($0.0) }
                        }
                        Picker("Pause duration", selection: Binding(
                            get: { config.dtmf.idleTime },
                            set: { value in model.setDTMF { $0.idleTime = value } })) {
                            ForEach(Options.dtmf["idleTime"] ?? [], id: \.0) { Text($0.1).tag($0.0) }
                        }
                        Picker("Separator", selection: Binding(
                            get: { config.dtmf.separator },
                            set: { value in model.setDTMF { $0.separator = value } })) {
                            ForEach(Options.dtmf["separator"] ?? [], id: \.0) { Text($0.1).tag($0.0) }
                        }
                        Picker("Group call code", selection: Binding(
                            get: { config.dtmf.groupCall },
                            set: { value in model.setDTMF { $0.groupCall = value } })) {
                            ForEach(Options.dtmf["groupCall"] ?? [], id: \.0) { Text($0.1).tag($0.0) }
                        }
                        Picker("Call hold time", selection: Binding(
                            get: { config.dtmf.hangUp },
                            set: { value in model.setDTMF { $0.hangUp = value } })) {
                            ForEach(Options.dtmf["hangUp"] ?? [], id: \.0) { Text($0.1).tag($0.0) }
                        }
                    }
                    Section("Start and end codes") {
                        HStack {
                            Text("Transmit start code")
                            Spacer()
                            TextField("up to 16", text: Binding(
                                get: { config.dtmf.onlineCode },
                                set: { value in model.setDTMF { $0.onlineCode = value } }))
                                .frame(width: 150)
                                .textFieldStyle(.roundedBorder)
                                .monospaced()
                        }
                        HStack {
                            Text("Transmit end code")
                            Spacer()
                            TextField("up to 16", text: Binding(
                                get: { config.dtmf.offlineCode },
                                set: { value in model.setDTMF { $0.offlineCode = value } }))
                                .frame(width: 150)
                                .textFieldStyle(.roundedBorder)
                                .monospaced()
                        }
                    }
                    Section("Call groups") {
                        ForEach(0..<20, id: \.self) { index in
                            HStack {
                                Text("\(index + 1)")
                                    .monospacedDigit()
                                    .frame(width: 22, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("code", text: Binding(
                                    get: { config.dtmf.groups[index] },
                                    set: { value in model.setDTMF { $0.groups[index] = value } }))
                                    .frame(width: 92)
                                    .textFieldStyle(.roundedBorder)
                                    .monospaced()
                                    .lineLimit(1)
                                TextField("name", text: Binding(
                                    get: { config.dtmf.groupNames[index] },
                                    set: { value in model.setDTMF { $0.groupNames[index] = value } }))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minWidth: 160)
                                    .lineLimit(1)
                            }
                        }
                    }
                } else {
                    Text("Load an image first.").foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct PaneHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }
}
