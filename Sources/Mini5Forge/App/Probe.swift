// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 duderayuh
//
// Headless BLE probe, used for verifying the Bluetooth stack and finding the radio.
//
//   open -a "MINI-5 Forge.app" --args --probe --out /tmp/probe.json
//
// Writes what the Mac can see, then exits. No radio commands are sent.

import Foundation
import CoreBluetooth
import AppKit

final class ProbeScanner: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager?
    private var seen: [String: (id: String, name: String, rssi: Int, services: [String], count: Int)] = [:]
    private var deadline: Date = Date()
    private let outPath: String
    private var timer: Timer?

    init(outPath: String) {
        self.outPath = outPath
        super.init()
    }

    func run(seconds: TimeInterval = 14) {
        deadline = Date().addingTimeInterval(seconds)
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Date() > self.deadline { self.finish(reason: "scan window elapsed") }
        }
    }

    private func finish(reason: String) {
        timer?.invalidate()
        central?.stopScan()
        let state = describe(central?.state ?? .unknown)
        let entries = seen.values.sorted { $0.name < $1.name }.map {
            ["id": $0.id, "name": $0.name, "rssi": "\($0.rssi)",
             "services": $0.services.joined(separator: ","), "advertisements": "\($0.count)"]
        }
        var payload: [String: Any] = [
            "bluetooth_state": state,
            "reason": reason,
            "device_count": entries.count,
            "devices": entries,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
           let text = String(data: data, encoding: .utf8) {
            try? text.write(toFile: outPath, atomically: true, encoding: .utf8)
            print(text)
        }
        NSApp.terminate(nil)
        exit(0)
    }

    private func describe(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: return "poweredOn"
        case .poweredOff: return "poweredOff"
        case .unauthorized: return "unauthorized"
        case .unsupported: return "unsupported"
        case .resetting: return "resetting"
        case .unknown: return "unknown"
        @unknown default: return "other"
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("state:", describe(central.state))
        guard central.state == .poweredOn else {
            if central.state == .unauthorized || central.state == .unsupported {
                finish(reason: "bluetooth unavailable")
            }
            return
        }
        central.scanForPeripherals(withServices: [CBUUID(string: "FFE0")],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            central.stopScan()
            central.scanForPeripherals(withServices: nil,
                                       options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let services = ((advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? [])
            .map { $0.uuidString }
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "(unnamed)"
        let key = peripheral.identifier.uuidString
        if var existing = seen[key] {
            existing.count += 1
            existing.rssi = RSSI.intValue
            seen[key] = existing
        } else {
            seen[key] = (key, name, RSSI.intValue, services, 1)
        }
    }
}
