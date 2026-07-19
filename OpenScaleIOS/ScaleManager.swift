// SPDX-License-Identifier: GPL-3.0-or-later
//
// OpenTara – lokale Körperwaagen-App

import Foundation
import CoreBluetooth

/// Sucht per BLE nach unterstützten Waagen und wertet sie über die registrierten
/// `ScaleDriver` aus – passiv (Advertisement) oder per Verbindung (GATT).
final class ScaleManager: NSObject, ObservableObject {

    @Published var statusText: String = String(localized: "Starte…")
    @Published var isScanning: Bool = false
    @Published var bluetoothReady: Bool = false

    @Published var lastWeightKg: Double?
    @Published var lastImpedance: Int?
    @Published var lastStabilized: Bool = false
    @Published var lastRawHex: String = ""
    @Published var lastDeviceName: String = ""
    @Published var log: [String] = []

    /// Wird aufgerufen, sobald eine stabilisierte Messung eintrifft.
    var onStabilizedMeasurement: ((ScaleMeasurement) -> Void)?

    private var central: CBCentralManager!
    private let drivers = ScaleDriverRegistry.all

    // Aktive Verbindung (für Verbindungs-Treiber)
    private var activePeripheral: CBPeripheral?
    private var activeDriver: ScaleDriver?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard central.state == .poweredOn else {
            statusText = String(localized: "Bluetooth nicht bereit")
            return
        }
        log.removeAll()
        isScanning = true
        statusText = String(localized: "Suche Waage… jetzt barfuß draufstellen")
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func stopScan() {
        central.stopScan()
        if let p = activePeripheral { central.cancelPeripheralConnection(p) }
        activePeripheral = nil
        activeDriver = nil
        isScanning = false
        statusText = String(localized: "Scan gestoppt")
    }

    private func appendLog(_ line: String) {
        log.insert(line, at: 0)
        if log.count > 200 { log.removeLast(log.count - 200) }
    }

    private func handle(_ reading: ScaleReading) {
        lastRawHex = reading.rawHex
        lastWeightKg = reading.weightKg
        lastImpedance = reading.impedance
        lastStabilized = reading.isStabilized
        lastDeviceName = reading.source

        statusText = String(
            format: "%.2f kg%@%@",
            reading.weightKg,
            reading.isStabilized ? " ✓ stabil" : " …",
            reading.impedance != nil ? " · Imp \(reading.impedance!)Ω" : " · barfuß fehlt"
        )
        appendLog(String(
            format: "[%@] w=%.2f imp=%@ stab=%d  %@",
            reading.source, reading.weightKg, reading.impedance.map(String.init) ?? "-",
            reading.isStabilized ? 1 : 0, reading.rawHex
        ))

        if reading.isStabilized && !reading.weightRemoved {
            let m = ScaleMeasurement(
                date: Date(),
                weightKg: reading.weightKg,
                impedance: reading.impedance,
                isStabilized: true,
                rawHex: reading.rawHex
            )
            onStabilizedMeasurement?(m)
        }
    }
}

// MARK: - Central (Scan + Verbindungsaufbau)

extension ScaleManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            bluetoothReady = true
            statusText = String(localized: "Bluetooth bereit – auf Suchen tippen")
        case .poweredOff:
            bluetoothReady = false
            statusText = String(localized: "Bluetooth ist ausgeschaltet")
        case .unauthorized:
            bluetoothReady = false
            statusText = String(localized: "Bluetooth-Berechtigung fehlt (Einstellungen)")
        case .unsupported:
            bluetoothReady = false
            statusText = String(localized: "Bluetooth wird nicht unterstützt")
        default:
            bluetoothReady = false
            statusText = String(localized: "Bluetooth nicht verfügbar")
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {

        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let serviceData = (advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]) ?? [:]
        let advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []

        // 1) Advertisement-Treiber: Daten stecken schon im Broadcast.
        for driver in drivers where driver.kind == .advertisement
            && driver.matches(name: name, serviceData: serviceData, advertised: advertised) {
            if let reading = driver.parse(serviceData: serviceData, localName: name) {
                DispatchQueue.main.async { self.handle(reading) }
                return
            }
        }

        // 2) Verbindungs-Treiber: koppeln und GATT abonnieren (nur eine Verbindung zugleich).
        guard activePeripheral == nil else { return }
        for driver in drivers where driver.kind == .connection
            && driver.matches(name: name, serviceData: serviceData, advertised: advertised) {
            activeDriver = driver
            activePeripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
            let label = name ?? peripheral.identifier.uuidString
            DispatchQueue.main.async {
                self.statusText = String(localized: "Verbinde mit \(label)…")
                self.appendLog("verbinde [\(driver.displayName)] \(label)")
            }
            return
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(activeDriver?.connectionProfile?.serviceUUIDs)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async { self.appendLog("Verbindung fehlgeschlagen") }
        activePeripheral = nil
        activeDriver = nil
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral == activePeripheral {
            activePeripheral = nil
            activeDriver = nil
        }
    }
}

// MARK: - Peripheral (GATT-Discovery + Notifications)

extension ScaleManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let notify = activeDriver?.connectionProfile?.notifyUUIDs ?? []
        for ch in service.characteristics ?? [] where notify.contains(ch.uuid) {
            peripheral.setNotifyValue(true, for: ch)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let driver = activeDriver, let data = characteristic.value else { return }
        if let reading = driver.handle(characteristic: characteristic.uuid, data: data) {
            DispatchQueue.main.async { self.handle(reading) }
        } else {
            let hex = [UInt8](characteristic.value ?? Data()).map { String(format: "%02x", $0) }.joined()
            DispatchQueue.main.async { self.appendLog("\(characteristic.uuid.uuidString): \(hex)") }
        }
    }
}
