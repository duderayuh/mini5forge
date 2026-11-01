// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 duderayuh
//
// Mini5 Forge — app shell, toolbar and connection sheet.

import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var model: ForgeModel
    @State private var showConnect = false

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model)
                .frame(width: 186)
            Divider()
            VStack(spacing: 0) {
                detail
                Divider()
                StatusBar(model: model)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $showConnect) {
            ConnectSheet(link: model.link) { showConnect = false }
        }
        .sheet(item: $model.writePreview) { preview in
            WriteSheet(model: model, preview: preview)
        }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .onAppear { if !model.hasDocument { model.newDocument() } }
    }

    @ViewBuilder private var detail: some View {
        switch model.pane {
        case .channels: ChannelsPane(model: model)
        case .settings: SettingsPane(model: model)
        case .vfo: VFOPane(model: model)
        case .dtmf: DTMFPane(model: model)
        case .inspect: InspectPane(model: model)
        case .log: LogPane(model: model)
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                if model.link.phase == .scanning {
                    model.link.stopScan()
                } else {
                    model.link.startScan()
                    showConnect = true
                }
            } label: {
                Label(model.link.isConnected ? "Radio" : "Connect",
                      systemImage: model.link.isConnected
                        ? "antenna.radiowaves.left.and.right.circle.fill"
                        : "antenna.radiowaves.left.and.right")
            }
            .help("Scan for and connect to your MINI-5 over Bluetooth")

            Button { model.readRadio() } label: {
                Label("Read", systemImage: "arrow.down.circle")
            }
            .disabled(!model.canRead)
            .help("Read the radio into the editor")

            Button { model.prepareWrite() } label: {
                Label("Write", systemImage: "arrow.up.circle.fill")
            }
            .disabled(!model.canWrite)
            .help("Write the edited configuration back to the radio")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("New document from defaults") { model.newDocument() }
                Button("Open image…") { model.openImage() }
                Divider()
                Button("Save image…") { model.saveImage() }
                Button("Save pre-flight backup…") { model.saveBackup() }
                Divider()
                Button("Import channels from CSV…") { model.importCSV() }
                Button("Export channels to CSV…") { model.exportCSV() }
                Divider()
                Button("Clear all channels") { model.wipeChannels() }
            } label: {
                Label("File", systemImage: "doc")
            }
        }
    }
}

struct Sidebar: View {
    @ObservedObject var model: ForgeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Pane.allCases) { pane in
                Button {
                    model.pane = pane
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: pane.symbol)
                            .frame(width: 18)
                            .foregroundStyle(model.pane == pane ? Color.accentColor : Color.secondary)
                        Text(pane.title)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(model.pane == pane ? Color.accentColor.opacity(0.20) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text("MINI-5 Forge").font(.caption.bold())
                Text("local · no account · no cloud").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

struct StatusBar: View {
    @ObservedObject var model: ForgeModel

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.link.isConnected ? Color.green : (model.link.phase == .scanning ? Color.orange : Color.secondary))
                .frame(width: 8, height: 8)
            Text(model.link.isConnected ? "connected · \(model.link.connectedName ?? "radio")" : "not connected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider().frame(height: 12)
            Text(model.status)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let busy = model.busy {
                ProgressView(value: model.progress).frame(width: 110)
                Text("\(busy) \(model.progressNote)").font(.caption.monospacedDigit())
            } else if model.dirty {
                Label("unsaved edits", systemImage: "pencil")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            } else if model.lastVerified {
                Label("verified on radio", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(Color.green)
            }
            Text(model.sourceLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct ConnectSheet: View {
    @ObservedObject var link: RadioLink
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nearby radios").font(.headline)
                Spacer()
                Button(link.phase == .scanning ? "Stop" : "Scan again") {
                    if link.phase == .scanning { link.stopScan() } else { link.startScan() }
                }
            }
            Text(link.scannedEverything
                 ? "Showing every nearby BLE device. The MINI-5 advertises service FFE0 — its name usually contains 5RMINI or MINI."
                 : "Listening for devices that advertise the MINI-5 programming service (FFE0).")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(link.discovered) { radio in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(radio.name).font(.body.weight(.medium))
                        Text(radio.advertisesProgrammingService ? "advertises FFE0 — looks right" : "no FFE0 advertisement")
                            .font(.caption2)
                            .foregroundStyle(radio.advertisesProgrammingService ? Color.green : Color.secondary)
                    }
                    Spacer()
                    Text("\(radio.rssi) dBm")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button("Connect") {
                        Task {
                            do {
                                try await link.connect(radio)
                                dismiss()
                            } catch {
                                link.note("Connect failed: \(error.localizedDescription)")
                            }
                        }
                    }
                    .disabled(link.phase == .connecting)
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 230)
            .overlay {
                if link.discovered.isEmpty {
                    Text(link.phase == .scanning ? "Scanning…" : "Nothing found yet.")
                        .foregroundStyle(.secondary)
                }
            }

            if let connected = link.connectedName {
                Label("Connected to \(connected)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
                    .font(.callout)
            }

            HStack(alignment: .bottom) {
                Text("Power the radio on and keep it near the Mac. It drops the Bluetooth link after a few idle minutes — reconnect here if a read stalls.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
            }
        }
        .padding(18)
        .frame(width: 600, height: 450)
        .onAppear { if link.discovered.isEmpty { link.startScan() } }
    }
}
