// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 duderayuh
//
// Mini5 Forge — channel table and editor.

import SwiftUI

struct ChannelsPane: View {
    @ObservedObject var model: ForgeModel
    @State private var selection: Set<Int> = []
    @State private var draft: ChannelDraft?
    @State private var showVacant = false

    private var rows: [Channel] {
        guard let channels = model.config?.channels else { return [] }
        var list = channels
        if !showVacant { list = list.filter { !$0.isVacant } }
        let query = model.searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(query)
                || $0.rxFreq.contains(query)
                || $0.txFreq.contains(query)
                || String($0.slot) == query
            }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Table(rows, selection: $selection) {
                TableColumn("#") { channel in
                    Text("\(channel.slot)")
                        .monospacedDigit()
                        .foregroundStyle(channel.isVacant ? .secondary : .primary)
                }
                .width(40)
                TableColumn("Name") { channel in
                    Text(channel.isVacant ? "—" : channel.name)
                        .foregroundStyle(channel.isVacant ? .secondary : .primary)
                }
                .width(min: 88, ideal: 108, max: 200)
                TableColumn("Receive") { channel in
                    Text(channel.rxFreq.isEmpty ? "—" : channel.rxFreq).monospacedDigit()
                }
                .width(min: 84, ideal: 90)
                TableColumn("Transmit") { channel in
                    Text(channel.isVacant ? "—" : (channel.txFreq.isEmpty ? "off" : channel.txFreq))
                        .monospacedDigit()
                        .foregroundStyle(channel.txFreq.isEmpty ? .secondary : .primary)
                }
                .width(min: 84, ideal: 90)
                TableColumn("Shift") { channel in
                    Text(channel.offsetDescription).font(.caption).foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 78)
                TableColumn("Tone RX / TX") { channel in
                    Text(channel.isVacant ? "—" : "\(channel.rxTone) / \(channel.txTone)")
                        .font(.caption.monospacedDigit())
                }
                .width(min: 98, ideal: 106)
                TableColumn("Power") { channel in
                    Text(channel.isVacant ? "" : (channel.txPower == 0 ? "High" : "Low")).font(.caption)
                }
                .width(48)
                TableColumn("BW") { channel in
                    Text(channel.isVacant ? "" : (channel.bandwide == 0 ? "Wide" : "Narrow")).font(.caption)
                }
                .width(46)
                TableColumn("Scan") { channel in
                    Text(channel.isVacant ? "" : (channel.scanAdd == 1 ? "in" : "skip")).font(.caption)
                }
                .width(42)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .onChange(of: selection) { newValue in
                if newValue.count == 1 { model.selectedSlot = newValue.first }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("\(model.config?.populatedChannels.count ?? 0) of \(RadioLayout.usableChannels) programmed")
                .font(.subheadline.weight(.medium))
            Divider().frame(height: 14)
            Toggle("Show empty slots", isOn: $showVacant)
                .toggleStyle(.checkbox)
                .font(.caption)
            Spacer()
            TextField("filter name or frequency", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
            Button {
                addChannel()
            } label: { Label("Add", systemImage: "plus") }
                .help("Add a channel in the first empty slot")
            Button {
                editSelected()
            } label: { Label("Edit", systemImage: "pencil") }
                .disabled(selection.count != 1)
            Button(role: .destructive) {
                clearSelected()
            } label: { Label("Clear", systemImage: "trash") }
                .disabled(selection.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func addChannel() {
        guard let config = model.config,
              let vacant = config.channels.first(where: { $0.isVacant }) else { return }
        var channel = vacant
        let neighbour = config.channels.filter { !$0.isVacant }.last
        channel.rxFreq = neighbour?.rxFreq ?? "146.52000"
        channel.txFreq = channel.rxFreq
        channel.rxTone = neighbour?.rxTone ?? "OFF"
        channel.txTone = neighbour?.txTone ?? "OFF"
        channel.txPower = neighbour?.txPower ?? 0
        channel.bandwide = neighbour?.bandwide ?? 0
        channel.scanAdd = 1
        channel.name = ""
        draft = ChannelDraft(channel: channel)
    }

    private func editSelected() {
        guard let slot = selection.first,
              let channel = model.config?.channels.first(where: { $0.slot == slot }) else { return }
        draft = ChannelDraft(channel: channel)
    }

    private func clearSelected() {
        guard var config = model.config else { return }
        for slot in selection where slot >= 1 && slot <= config.channels.count {
            config.channels[slot - 1] = Channel(slot: slot)
        }
        model.replaceChannels(config.channels)
        selection.removeAll()
    }
}

struct ChannelDraft: Identifiable {
    let id = UUID()
    var channel: Channel
}

struct ChannelEditor: View {
    @ObservedObject var model: ForgeModel
    @Binding var draft: ChannelDraft
    var dismiss: () -> Void
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Channel \(draft.channel.slot)").font(.headline)
                Spacer()
                Text(draft.channel.offsetDescription).font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)

            Divider()

            Form {
                Section("Frequency") {
                    TextField("Receive (MHz)", text: Binding(
                        get: { draft.channel.rxFreq },
                        set: { draft.channel.rxFreq = $0 }))
                        .monospaced()
                    TextField("Transmit (MHz) — leave empty for receive-only", text: Binding(
                        get: { draft.channel.txFreq },
                        set: { draft.channel.txFreq = $0 }))
                        .monospaced()
                    HStack {
                        Button("Simplex (TX = RX)") {
                            draft.channel.txFreq = draft.channel.rxFreq
                        }
                        Button("Receive only") { draft.channel.txFreq = "" }
                        Spacer()
                    }
                }

                Section("Label") {
                    TextField("Name (up to 12 bytes)", text: Binding(
                        get: { draft.channel.name },
                        set: { draft.channel.name = $0 }))
                }

                Section("Tones") {
                    Picker("Receive tone", selection: Binding(
                        get: { draft.channel.rxTone },
                        set: { draft.channel.rxTone = $0 })) {
                        ForEach(ToneTable.all, id: \.self) { Text($0 == "OFF" ? "Off" : $0).tag($0) }
                    }
                    Picker("Transmit tone", selection: Binding(
                        get: { draft.channel.txTone },
                        set: { draft.channel.txTone = $0 })) {
                        ForEach(ToneTable.all, id: \.self) { Text($0 == "OFF" ? "Off" : $0).tag($0) }
                    }
                    HStack {
                        Button("Copy RX tone to TX") { draft.channel.txTone = draft.channel.rxTone }
                        Button("Clear both tones") {
                            draft.channel.rxTone = "OFF"; draft.channel.txTone = "OFF"
                        }
                        Spacer()
                    }
                }

                Section("Radio behaviour") {
                    Picker("Transmit power", selection: Binding(
                        get: { draft.channel.txPower },
                        set: { draft.channel.txPower = $0 })) {
                        Text("High").tag(0)
                        Text("Low").tag(1)
                    }
                    Picker("Bandwidth", selection: Binding(
                        get: { draft.channel.bandwide },
                        set: { draft.channel.bandwide = $0 })) {
                        Text("Wide").tag(0)
                        Text("Narrow").tag(1)
                    }
                    Picker("Scan", selection: Binding(
                        get: { draft.channel.scanAdd },
                        set: { draft.channel.scanAdd = $0 })) {
                        Text("Include").tag(1)
                        Text("Skip").tag(0)
                    }
                    Picker("Busy-channel lock", selection: Binding(
                        get: { draft.channel.busyLock },
                        set: { draft.channel.busyLock = $0 })) {
                        Text("Off").tag(0); Text("On").tag(1)
                    }
                    Picker("PTT ID", selection: Binding(
                        get: { draft.channel.pttid },
                        set: { draft.channel.pttid = $0 })) {
                        ForEach(Options.channel["pttid"] ?? [], id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Picker("DTMF group", selection: Binding(
                        get: { draft.channel.signalGroup },
                        set: { draft.channel.signalGroup = $0 })) {
                        ForEach(1...20, id: \.self) { Text("Group \($0)").tag($0 - 1) }
                    }
                }
            }
            .formStyle(.grouped)

            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save channel") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 520, height: 620)
    }

    private func save() {
        var channel = draft.channel
        if let padded = FieldCodec.padFrequency(channel.rxFreq) {
            channel.rxFreq = padded
        } else {
            problem = "Receive frequency needs to look like 146.52000."
            return
        }
        if !channel.txFreq.trimmingCharacters(in: .whitespaces).isEmpty {
            if let padded = FieldCodec.padFrequency(channel.txFreq) {
                channel.txFreq = padded
            } else {
                problem = "Transmit frequency needs to look like 448.90000, or leave it empty."
                return
            }
        } else {
            channel.txFreq = ""
        }
        if FieldCodec.encodeName(channel.name, maxBytes: 12) == nil {
            problem = "The radio stores names as GBK, max 12 bytes. Shorten it."
            return
        }
        draft.channel = channel
        model.updateChannel(channel)
        dismiss()
    }
}
