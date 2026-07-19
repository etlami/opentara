// SPDX-License-Identifier: GPL-3.0-or-later
//
// Freescale – lokale Körperwaagen-App

import Foundation
import CoreBluetooth

/// Xiaomi Mi Smart Scale (v1, ohne Körperzusammensetzung) – nur Gewicht.
/// Sendet passiv im Advertisement unter Service 0x181D.
///
/// EXPERIMENTELL: aus openScale portiert, noch nicht mit Hardware verifiziert.
/// Byte-Layout (10 Byte): [0] Steuerbyte, [1-2] Gewicht (LE), [3-9] Datum/Zeit.
struct MiSmartScaleV1Driver: ScaleDriver {
    let displayName = "Xiaomi Mi Smart Scale (v1, nur Gewicht)"
    let isTested = false
    let kind = ScaleConnectionKind.advertisement

    private let service = CBUUID(string: "181D")

    func matches(name: String?, serviceData: [CBUUID: Data], advertised: [CBUUID]) -> Bool {
        // Nur wenn Messdaten wirklich im Advertisement stecken (grenzt SIG-Waagen ab).
        if let d = serviceData[service] { return d.count >= 10 }
        return false
    }

    func parse(serviceData: [CBUUID: Data], localName: String?) -> ScaleReading? {
        guard let data = serviceData[service] else { return nil }
        let b = [UInt8](data)
        guard b.count >= 10 else { return nil }

        let hex = b.map { String(format: "%02x", $0) }.joined(separator: " ")
        let ctrl = b[0]
        let isStabilized  = (ctrl & (1 << 5)) != 0
        let weightRemoved = (ctrl & (1 << 7)) != 0
        let raw = Int(b[1]) | (Int(b[2]) << 8)

        let isLbs   = (ctrl & (1 << 0)) != 0
        let isCatty = (ctrl & (1 << 4)) != 0
        let kg: Double
        if isLbs {
            kg = (Double(raw) / 100.0) * 0.45359237
        } else if isCatty {
            kg = (Double(raw) / 100.0) * 0.5
        } else {
            kg = Double(raw) / 200.0
        }

        return ScaleReading(weightKg: kg, impedance: nil, isStabilized: isStabilized,
                            weightRemoved: weightRemoved, rawHex: hex, source: displayName)
    }
}
