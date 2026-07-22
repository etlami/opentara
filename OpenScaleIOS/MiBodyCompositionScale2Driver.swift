// SPDX-License-Identifier: GPL-3.0-or-later
//
// OpenTara – lokale Körperwaagen-App

import Foundation
import CoreBluetooth

/// Xiaomi Mi Body Composition Scale 2 (BLE-Name "MIBFS").
/// Liest Gewicht + Impedanz passiv aus den Advertisement-Servicedaten (0x181B).
struct MiBodyCompositionScale2Driver: ScaleDriver {
    let displayName = "Xiaomi Mi Body Composition Scale 2"
    let isTested = true
    let kind = ScaleConnectionKind.advertisement

    private let service = CBUUID(string: "181B")

    func matches(name: String?, serviceData: [CBUUID: Data], advertised: [CBUUID]) -> Bool {
        serviceData[service] != nil
    }

    func parse(serviceData: [CBUUID: Data], localName: String?) -> ScaleReading? {
        guard let data = serviceData[service] else { return nil }
        let bytes = [UInt8](data)
        guard bytes.count >= 13 else { return nil }

        let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")

        let ctrl0 = bytes[0]
        let ctrl1 = bytes[1]
        let isStabilized  = (ctrl1 & (1 << 5)) != 0
        let hasImpedance  = (ctrl1 & (1 << 1)) != 0
        let weightRemoved = (ctrl1 & (1 << 7)) != 0

        let rawImpedance = Int(bytes[9])  | (Int(bytes[10]) << 8)
        let rawWeight    = Int(bytes[11]) | (Int(bytes[12]) << 8)

        let isLbs   = (ctrl0 & (1 << 0)) != 0
        let isCatty = (ctrl0 & (1 << 4)) != 0
        let weightKg: Double
        if isLbs {
            weightKg = (Double(rawWeight) / 100.0) * 0.45359237
        } else if isCatty {
            weightKg = (Double(rawWeight) / 100.0) * 0.5
        } else {
            weightKg = Double(rawWeight) / 200.0
        }

        let impedance: Int? = (hasImpedance && rawImpedance > 0 && rawImpedance < 3000) ? rawImpedance : nil

        return ScaleReading(
            weightKg: weightKg,
            impedance: impedance,
            isStabilized: isStabilized,
            weightRemoved: weightRemoved,
            rawHex: hex,
            source: displayName
        )
    }
}
