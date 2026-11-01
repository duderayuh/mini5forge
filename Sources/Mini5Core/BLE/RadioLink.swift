// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 duderayuh
//
// Mini5 Forge — CoreBluetooth transport for the Baofeng MINI-5 programming protocol.
//
// Wire protocol (reverse-engineered, documented publicly):
//   service 0xFFE0, characteristic 0xFFE1, notifications on the same characteristic
//   handshake  "PROGRAMCOLORPROU" -> 0x06
//   config     0x46 -> 16 bytes
//   identity   0x4D -> 15 bytes, first 8 = model ("5RMINI ")
//   init       53 45 4E 44 21 05 0D 01 01 01 04 11 08 05 0D 0D 01 11 0F 09 12 09 10 04 00 -> 0x06
//   read       0x52 addrHi addrLo 0x40 -> 0x52 addrHi addrLo 0x40 + 64 bytes
//   write      0x57 addrHi addrLo 0x80 + 128 bytes -> 0x06
//   finish     0x45

import Foundation
import CoreBluetooth

public struct DiscoveredRadio: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public let advertisesProgrammingService: Bool
    let peripheral: CBPeripheral
}

public enum RadioLinkError: LocalizedError {
    case bluetoothUnavailable(String)
    case noRadioSelected
    case connectFailed(String)
    case disconnected
    case timeout(String)
    case protocolViolation(String)
    case wrongModel(String)

    public var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable(let detail): return "Bluetooth unavailable: \(detail)"
        case .noRadioSelected: return "Pick a radio first."
        case .connectFailed(let detail): return "Could not connect: \(detail)"
        case .disconnected: return "The radio disconnected."
        case .timeout(let stage): return "\(stage) timed out."
        case .protocolViolation(let detail): return "Unexpected reply: \(detail)"
        case .wrongModel(let model): return "That device reports itself as \(model), not a MINI-5."
        }
    }
}

public final class RadioLink: NSObject, ObservableObject {

    public enum Phase: Equatable {
        case idle, scanning, connecting, ready, working
    }

    public static let serviceUUID = CBUUID(string: "FFE0")
    public static let characteristicUUID = CBUUID(string: "FFE1")
    static let magic = Array("PROGRAMCOLORPROU".utf8)
    static let initFrame: [UInt8] = [
        0x53, 0x45, 0x4E, 0x44, 0x21, 0x05, 0x0D, 0x01, 0x01, 0x01, 0x04, 0x11, 0x08,
        0x05, 0x0D, 0x0D, 0x01, 0x11, 0x0F, 0x09, 0x12, 0x09, 0x10, 0x04, 0x00,
    ]
    static let responseTimeout: TimeInterval = 4.0

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var discovered: [DiscoveredRadio] = []
    @Published public private(set) var connectedName: String?
    @Published public private(set) var model: String?
    @Published public private(set) var scannedEverything = false
    @Published public private(set) var log: [String] = []

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var rx: [UInt8] = []

    private var scanFallback: DispatchWorkItem?
    private var wantsScan = false
    private var scanning = false
    private var pending: (needed: Int, continuation: CheckedContinuation<[UInt8], Error>, timeout: DispatchWorkItem)?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var serviceContinuation: CheckedContinuation<Void, Error>?
    private var characteristicContinuation: CheckedContinuation<Void, Error>?
    private var notifyContinuation: CheckedContinuation<Void, Error>?
    private var readyContinuation: CheckedContinuation<Void, Error>?

    public var isConnected: Bool { characteristic != nil && peripheral?.state == .connected }

    /// Optional sink for live console output (headless modes).
    public var onLog: ((String) -> Void)?

    public func note(_ message: String) {
        let stamp = Self.timeFormatter.string(from: Date())
        log.append("[\(stamp)] \(message)")
        if log.count > 400 { log.removeFirst(log.count - 400) }
        onLog?(message)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: - Central

    private func ensureCentral() -> CBCentralManager {
        if let central { return central }
        let manager = CBCentralManager(delegate: self, queue: .main,
                                       options: [CBCentralManagerOptionShowPowerAlertKey: true])
        central = manager
        return manager
    }

    public func startScan() {
        let manager = ensureCentral()
        wantsScan = true
        discovered.removeAll()
        scannedEverything = false
        phase = .scanning
        guard manager.state == .poweredOn else {
            // First call usually lands here: CBCentralManager reports .unknown until it powers up.
            note("Waiting for Bluetooth to power on…")
            return
        }
        beginScanning(manager)
    }

    private func beginScanning(_ manager: CBCentralManager) {
        guard !scanning else { return }
        scanning = true
        manager.scanForPeripherals(withServices: [Self.serviceUUID],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        note("Scanning for radios advertising 0xFFE0…")
        let fallback = DispatchWorkItem { [weak self] in
            guard let self, self.wantsScan, self.phase == .scanning else { return }
            self.scannedEverything = true
            self.note("No 0xFFE0 advertisement yet — listing every nearby BLE device.")
            self.central?.stopScan()
            self.central?.scanForPeripherals(withServices: nil,
                                             options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
        scanFallback = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: fallback)
    }

    public func stopScan() {
        scanFallback?.cancel()
        scanFallback = nil
        wantsScan = false
        scanning = false
        central?.stopScan()
        if phase == .scanning { phase = isConnected ? .ready : .idle }
    }

    public func connect(_ radio: DiscoveredRadio) async throws {
        stopScan()
        if isConnected { disconnect() }
        phase = .connecting
        discovered.removeAll()
        note("Connecting to \(radio.name)…")
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connectContinuation = cont
            peripheral = radio.peripheral
            radio.peripheral.delegate = self
            central?.connect(radio.peripheral, options: nil)
            scheduleConnectTimeout()
        }
        try await discover()
        phase = .ready
        connectedName = radio.name
        note("Connected to \(radio.name).")
    }

    private var connectTimeout: DispatchWorkItem?

    private func scheduleConnectTimeout() {
        connectTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.connectContinuation?.resume(throwing: RadioLinkError.timeout("Connecting"))
            self.connectContinuation = nil
            self.phase = .idle
            if let peripheral = self.peripheral { self.central?.cancelPeripheralConnection(peripheral) }
        }
        connectTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    private func discover() async throws {
        guard let peripheral else { throw RadioLinkError.noRadioSelected }
        if peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) == nil {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                serviceContinuation = cont
                peripheral.discoverServices([Self.serviceUUID])
            }
        }
        if characteristic == nil {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                characteristicContinuation = cont
            }
            guard let characteristic else {
                throw RadioLinkError.connectFailed("Radio did not expose characteristic 0xFFE1.")
            }
            guard characteristic.isNotifying else {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    notifyContinuation = cont
                    peripheral.setNotifyValue(true, for: characteristic)
                }
                return
            }
        }
    }

    public func disconnect() {
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        clearConnection()
    }

    private func clearConnection() {
        characteristic = nil
        peripheral = nil
        rx.removeAll()
        phase = .idle
        connectedName = nil
        model = nil
        failPending(RadioLinkError.disconnected)
    }

    private func failPending(_ error: Error) {
        if let pending {
            pending.timeout.cancel()
            pending.continuation.resume(throwing: error)
            self.pending = nil
        }
        connectContinuation?.resume(throwing: error); connectContinuation = nil
        serviceContinuation?.resume(throwing: error); serviceContinuation = nil
        characteristicContinuation?.resume(throwing: error); characteristicContinuation = nil
        notifyContinuation?.resume(throwing: error); notifyContinuation = nil
        readyContinuation?.resume(throwing: error); readyContinuation = nil
    }

    // MARK: - Protocol

    private func send(_ bytes: [UInt8]) async throws {
        guard let peripheral, let characteristic else { throw RadioLinkError.disconnected }
        if !peripheral.canSendWriteWithoutResponse {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                readyContinuation = cont
            }
        }
        let data = Data(bytes)
        if characteristic.properties.contains(.writeWithoutResponse) {
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        } else if characteristic.properties.contains(.write) {
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        } else {
            throw RadioLinkError.connectFailed("Characteristic 0xFFE1 is not writable.")
        }
    }

    private func wait(for count: Int, stage: String) async throws -> [UInt8] {
        if rx.count >= count {
            let out = Array(rx.prefix(count))
            rx.removeFirst(count)
            return out
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[UInt8], Error>) in
            let work = DispatchWorkItem { [weak self] in
                guard let self, let pending = self.pending else { return }
                self.pending = nil
                pending.continuation.resume(throwing: RadioLinkError.timeout("\(stage) reply"))
            }
            pending = (needed: count, continuation: cont, timeout: work)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.responseTimeout, execute: work)
        }
    }

    private func request(_ bytes: [UInt8], expect count: Int, stage: String) async throws -> [UInt8] {
        guard isConnected else { throw RadioLinkError.disconnected }
        rx.removeAll()
        try await send(bytes)
        return try await wait(for: count, stage: stage)
    }

    /// Handshake + identity. Returns the radio's model string.
    @discardableResult
    public func identify() async throws -> String {
        let ack = try await request(Self.magic, expect: 1, stage: "Handshake")
        guard ack.first == 0x06 else {
            throw RadioLinkError.protocolViolation("handshake reply \(hex(ack))")
        }
        _ = try await request([0x46], expect: 16, stage: "Config read")
        let identity = try await request([0x4D], expect: 15, stage: "Identity")
        let name = String(decoding: identity.prefix(8), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.hasPrefix("5RMINI") else { throw RadioLinkError.wrongModel(name) }
        let initAck = try await request(Self.initFrame, expect: 1, stage: "Session start")
        guard initAck.first == 0x06 else {
            throw RadioLinkError.protocolViolation("init reply \(hex(initAck))")
        }
        model = name
        return name
    }

    /// Read every CPS-known block; returns the decoded image.
    public func readAll(progress: @escaping (Int, Int) -> Void) async throws -> RadioImage {
        try await identify()
        let addresses = Codec.readAddresses()
        var wire: [UInt8] = []
        wire.reserveCapacity(RadioLayout.imageSize)
        for (index, address) in addresses.enumerated() {
            let reply = try await request([0x52, UInt8((address >> 8) & 0xFF), UInt8(address & 0xFF), 0x40],
                                          expect: 68, stage: "Read block")
            guard reply.count == 68, reply[0] == 0x52,
                  (Int(reply[1]) << 8 | Int(reply[2])) == address, reply[3] == 0x40 else {
                throw RadioLinkError.protocolViolation("read header at 0x\(String(address, radix: 16))")
            }
            wire.append(contentsOf: reply[4...])
            if index % 32 == 0 { progress(index + 1, addresses.count) }
        }
        progress(addresses.count, addresses.count)
        _ = try? await request([0x45], expect: 1, stage: "Finish")
        rx.removeAll()
        return RadioImage(wire: wire)
    }

    /// Write the whole image and verify it by reading back.
    public func writeAll(_ image: RadioImage, progress: @escaping (Int, Int) -> Void) async throws -> RadioImage {
        try await identify()
        let frames = Codec.writeFrames(for: image)
        for (index, frame) in frames.enumerated() {
            let ack = try await request(frame, expect: 1, stage: "Write block 0x" + String(Codec.writeAddresses()[index], radix: 16))
            guard ack.first == 0x06 else {
                throw RadioLinkError.protocolViolation("write ack \(hex(ack)) at block \(index)")
            }
            progress(index + 1, frames.count)
        }
        note("All \(frames.count) write blocks acknowledged; reading back to verify…")
        return try await readAll { _, _ in }
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private static func describe(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: return "on"
        case .poweredOff: return "off"
        case .unauthorized: return "unauthorised (grant Bluetooth access in System Settings › Privacy & Security)"
        case .unsupported: return "unsupported on this Mac"
        case .resetting: return "resetting"
        case .unknown: return "still starting"
        @unknown default: return "in an unknown state"
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension RadioLink: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        note("Bluetooth is \(Self.describe(central.state)).")
        if central.state == .poweredOn {
            if wantsScan, !scanning { beginScanning(central) }
            return
        }
        scanning = false
        if phase == .scanning, central.state != .resetting { phase = .idle }
    }

    public func centralManager(_ central: CBCentralManager,
                               didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any],
                               rssi RSSI: NSNumber) {
        let advertisedServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let hasService = advertisedServices.contains(Self.serviceUUID)
        if scannedEverything && !hasService && peripheral.name == nil { return }
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "unnamed device"
        let entry = DiscoveredRadio(id: peripheral.identifier, name: name, rssi: RSSI.intValue,
                                   advertisesProgrammingService: hasService, peripheral: peripheral)
        if let existing = discovered.firstIndex(where: { $0.id == entry.id }) {
            discovered[existing] = entry
        } else {
            discovered.append(entry)
        }
        discovered.sort { a, b in
            if a.advertisesProgrammingService != b.advertisesProgrammingService {
                return a.advertisesProgrammingService
            }
            return a.rssi > b.rssi
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectTimeout?.cancel()
        connectContinuation?.resume()
        connectContinuation = nil
    }

    public func centralManager(_ central: CBCentralManager,
                               didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectTimeout?.cancel()
        connectContinuation?.resume(throwing: RadioLinkError.connectFailed(error?.localizedDescription ?? "unknown"))
        connectContinuation = nil
        phase = .idle
    }

    public func centralManager(_ central: CBCentralManager,
                               didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        note("Radio disconnected\(error.map { ": \($0.localizedDescription)" } ?? ".")")
        clearConnection()
    }
}

// MARK: - CBPeripheralDelegate

extension RadioLink: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let cont = serviceContinuation else { return }
        serviceContinuation = nil
        if let error {
            cont.resume(throwing: RadioLinkError.connectFailed(error.localizedDescription))
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            cont.resume(throwing: RadioLinkError.connectFailed("No 0xFFE0 service on this device."))
            return
        }
        peripheral.discoverCharacteristics([Self.characteristicUUID], for: service)
        cont.resume()
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let cont = characteristicContinuation else { return }
        characteristicContinuation = nil
        if let error {
            cont.resume(throwing: RadioLinkError.connectFailed(error.localizedDescription))
            return
        }
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.characteristicUUID }) else {
            cont.resume(throwing: RadioLinkError.connectFailed("Characteristic 0xFFE1 missing."))
            return
        }
        self.characteristic = characteristic
        cont.resume()
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard let cont = notifyContinuation else { return }
        notifyContinuation = nil
        if let error {
            cont.resume(throwing: RadioLinkError.connectFailed("Notifications: " + error.localizedDescription))
            return
        }
        guard characteristic.isNotifying else {
            cont.resume(throwing: RadioLinkError.connectFailed("The radio refused notification setup."))
            return
        }
        note("Notifications enabled; link ready.")
        cont.resume()
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        rx.append(contentsOf: [UInt8](data))
        drainIfPossible()
    }

    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        readyContinuation?.resume()
        readyContinuation = nil
    }

    private func drainIfPossible() {
        guard let pending else { return }
        if rx.count >= pending.needed {
            self.pending = nil
            pending.timeout.cancel()
            let out = Array(rx.prefix(pending.needed))
            rx.removeFirst(pending.needed)
            pending.continuation.resume(returning: out)
        }
    }
}
