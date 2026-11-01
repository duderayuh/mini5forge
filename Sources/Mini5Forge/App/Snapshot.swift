// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 duderayuh
//
// Offscreen snapshot mode: renders each pane to a PNG so the layout can be checked
// without screen-recording permission. Not used in normal operation.

import SwiftUI
import AppKit

@MainActor
enum Snapshotter {

    static func demoModel() -> ForgeModel {
        let model = ForgeModel()
        model.newDocument()
        var channels: [Channel] = []
        let seeds: [(String, String, String, Int)] = [
            ("CALLING", "146.52000", "146.52000", 1),
            ("W9RPT", "147.39000", "147.99000", 1),
            ("GMRS 1", "462.56250", "462.56250", 1),
            ("NOAA WX1", "162.55000", "162.55000", 1),
            ("AIR BAND", "121.50000", "121.50000", 0),
            ("DMR TEST", "443.90000", "448.90000", 1),
        ]
        for (index, seed) in seeds.enumerated() {
            var channel = Channel(slot: index + 1)
            channel.name = seed.0
            channel.rxFreq = seed.1
            channel.txFreq = seed.2
            channel.scanAdd = seed.3
            channel.txPower = index % 2
            channel.bandwide = index % 2
            channel.rxTone = index == 1 ? "91.5" : "OFF"
            channel.txTone = index == 1 ? "91.5" : "OFF"
            channels.append(channel)
        }
        model.replaceChannels(channels)
        model.status = "Demo document — 6 channels, not connected."
        return model
    }

    @discardableResult
    static func render(pane: Pane, to path: String) -> Bool {
        let model = demoModel()
        model.pane = pane
        let size = NSSize(width: 1180, height: 760)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "MINI-5 Forge"
        window.appearance = NSApp.effectiveAppearance
        let host = NSHostingView(rootView: ContentView(model: model).frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        var wrote = false
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
                wrote = true
            }
        }
        if !wrote {
            print("render failed for \(pane.rawValue)")
        } else {
            print("wrote \(path)")
        }
        window.orderOut(nil)
        return wrote
    }
}
