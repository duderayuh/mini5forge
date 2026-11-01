// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 duderayuh
//
// Mini5 Forge — entry point.

import SwiftUI
import AppKit
import CoreBluetooth

@main
struct Mini5ForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = ForgeModel()

    var body: some Scene {
        WindowGroup("MINI-5 Forge") {
            ContentView(model: model)
                .frame(minWidth: 940, minHeight: 600)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New document from defaults") { model.newDocument() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open image…") { model.openImage() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Save image…") { model.saveImage() }
                    .keyboardShortcut("s", modifiers: .command)
                Divider()
                Button("Import channels from CSV…") { model.importCSV() }
                Button("Export channels to CSV…") { model.exportCSV() }
            }
            CommandMenu("Radio") {
                Button("Scan for radios") { model.link.startScan() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Disconnect") { model.link.disconnect() }
                Divider()
                Button("Read from radio") { model.readRadio() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!model.canRead)
                Button("Write to radio…") { model.prepareWrite() }
                    .keyboardShortcut("w", modifiers: .command)
                    .disabled(!model.canWrite)
                Button("Save pre-flight backup…") { model.saveBackup() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var probe: ProbeScanner?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setvbuf(stdout, nil, _IONBF, 0)   // headless modes must stream output

        if let index = CommandLine.arguments.firstIndex(of: "--program") {
            let args = CommandLine.arguments
            func value(_ flag: String) -> String? {
                guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
                return args[i + 1]
            }
            guard index + 1 < args.count else {
                print("usage: Mini5Forge --program <channels.csv> [--dry-run] [--device NAME] [--device-id UUID] [--out DIR]")
                exit(2)
            }
            let csv = args[index + 1]
            let dryRun = args.contains("--dry-run")
            let device = value("--device")
            let deviceID = value("--device-id")
            let out = value("--out") ?? (NSHomeDirectory() + "/Developer/Mini5Forge/channels")
            NSApp.setActivationPolicy(.accessory)
            _ = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
                reason: "Programming the MINI-5")
            print("MINI-5 Forge programmer starting")
            print("  csv: \(csv)")
            print("  mode: \(dryRun ? "dry run (read + plan only)" : "READ + WRITE + VERIFY")")
            Task { @MainActor in
                let programmer = Programmer()
                let code = await programmer.run(csvPath: csv, deviceMatch: device, deviceID: deviceID, dryRun: dryRun, outDir: out)
                exit(code)
            }
            return
        }

        if CommandLine.arguments.contains("--probe") {
            let args = CommandLine.arguments
            let index = args.firstIndex(of: "--out")
            let out = index.flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "/tmp/mini5probe.json"
            NSApp.setActivationPolicy(.accessory)
            _ = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                                                      reason: "Scanning for the MINI-5")
            let scanner = ProbeScanner(outPath: out)
            probe = scanner
            scanner.run()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render") {
            let dir = index + 1 < CommandLine.arguments.count ? CommandLine.arguments[index + 1] : "/tmp/m5shots"
            NSApp.setActivationPolicy(.prohibited)
            DispatchQueue.main.async {
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                for pane in Pane.allCases {
                    Snapshotter.render(pane: pane, to: dir + "/" + pane.rawValue + ".png")
                }
                exit(0)
            }
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
