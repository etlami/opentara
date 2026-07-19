// SPDX-License-Identifier: GPL-3.0-or-later
//
// OpenTara – lokale Körperwaagen-App

import Foundation
import CoreBluetooth

/// Generischer Treiber für Waagen nach Bluetooth-SIG-Norm:
/// Weight Scale Service (0x181D) und/oder Body Composition Service (0x181B),
/// gelesen per Verbindung + GATT-Notifications.
///
/// EXPERIMENTELL: deckt viele normkonforme Waagen ab, aber jede muss noch
/// mit echter Hardware bestätigt werden (Roh-Log hilft beim Kalibrieren).
struct GenericSIGScaleDriver: ScaleDriver {
    let displayName = "Bluetooth-Standard-Waage (SIG)"
    let isTested = false
    let kind = ScaleConnectionKind.connection

    private let weightService  = CBUUID(string: "181D")
    private let bodyService    = CBUUID(string: "181B")
    private let weightMeas     = CBUUID(string: "2A9D")   // Weight Measurement
    private let bodyCompMeas   = CBUUID(string: "2A9C")   // Body Composition Measurement

    func matches(name: String?, serviceData: [CBUUID: Data], advertised: [CBUUID]) -> Bool {
        advertised.contains(weightService) || advertised.contains(bodyService)
    }

    var connectionProfile: ConnectionProfile? {
        ConnectionProfile(serviceUUIDs: [weightService, bodyService],
                          notifyUUIDs: [weightMeas, bodyCompMeas])
    }

    func handle(characteristic uuid: CBUUID, data: Data) -> ScaleReading? {
        let b = [UInt8](data)
        let hex = b.map { String(format: "%02x", $0) }.joined(separator: " ")
        if uuid == weightMeas { return parseWeight(b, hex: hex) }
        if uuid == bodyCompMeas { return parseBodyComposition(b, hex: hex) }
        return nil
    }

    // Weight Measurement (0x2A9D): [flags][weight LE]...
    private func parseWeight(_ b: [UInt8], hex: String) -> ScaleReading? {
        guard b.count >= 3 else { return nil }
        let imperial = (b[0] & 0x01) != 0
        let raw = Int(b[1]) | (Int(b[2]) << 8)
        let kg = imperial ? Double(raw) * 0.01 * 0.45359237 : Double(raw) * 0.005
        return ScaleReading(weightKg: kg, impedance: nil, isStabilized: true,
                            weightRemoved: false, rawHex: hex, source: displayName)
    }

    // Body Composition Measurement (0x2A9C): flags(2) + Körperfett(2) + optionale Felder.
    private func parseBodyComposition(_ b: [UInt8], hex: String) -> ScaleReading? {
        guard b.count >= 4 else { return nil }
        let flags = Int(b[0]) | (Int(b[1]) << 8)
        let imperial = (flags & 0x0001) != 0

        var i = 4  // nach Flags(2) + Körperfett(2)
        func u16() -> Int? {
            guard i + 1 < b.count else { return nil }
            let v = Int(b[i]) | (Int(b[i + 1]) << 8); i += 2; return v
        }
        // Optionale Felder in fester Reihenfolge überspringen:
        if flags & (1 << 1) != 0 { i += 7 }  // Zeitstempel
        if flags & (1 << 2) != 0 { i += 1 }  // User ID
        if flags & (1 << 3) != 0 { i += 2 }  // Grundumsatz
        if flags & (1 << 4) != 0 { i += 2 }  // Muskel %
        if flags & (1 << 5) != 0 { i += 2 }  // Muskelmasse
        if flags & (1 << 6) != 0 { i += 2 }  // fettfreie Masse
        if flags & (1 << 7) != 0 { i += 2 }  // Soft Lean Mass
        if flags & (1 << 8) != 0 { i += 2 }  // Körperwasser

        var impedance: Int?
        if flags & (1 << 9) != 0 { impedance = u16() }

        var kg: Double?
        if flags & (1 << 10) != 0, let w = u16() {
            kg = imperial ? Double(w) * 0.01 * 0.45359237 : Double(w) * 0.005
        }

        guard let weightKg = kg else { return nil }  // ohne Gewicht keine verwertbare Messung
        return ScaleReading(weightKg: weightKg, impedance: impedance, isStabilized: true,
                            weightRemoved: false, rawHex: hex, source: displayName)
    }
}
