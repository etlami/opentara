// SPDX-License-Identifier: GPL-3.0-or-later
//
// Freescale – lokale Körperwaagen-App
// Protokolle aus openScale (GPLv3, oliexdev/openScale) portiert.

import Foundation
import CoreBluetooth

/// Eine geräteunabhängige Einzelmessung, wie sie ein Treiber zurückgibt.
struct ScaleReading {
    var weightKg: Double
    var impedance: Int?          // Ohm, nil wenn nicht (barfuß) gemessen
    var isStabilized: Bool
    var weightRemoved: Bool
    var rawHex: String           // Roh-Bytes, nur zum Kalibrieren/Debuggen
    var source: String           // Name des Treibers/Geräts
}

/// Wie eine Waage ihre Daten liefert.
enum ScaleConnectionKind {
    case advertisement   // Daten stecken im BLE-Advertisement (z. B. Xiaomi)
    case connection      // Verbindung nötig: koppeln + GATT abonnieren
}

/// Beschreibt, welche GATT-Dienste/Characteristics ein Verbindungs-Treiber braucht.
struct ConnectionProfile {
    let serviceUUIDs: [CBUUID]   // zu suchende Dienste
    let notifyUUIDs: [CBUUID]    // zu abonnierende Characteristics (Notify/Indicate)
}

/// Schnittstelle für einen Waagen-Treiber. Pro Modell eine Implementierung.
/// Ungetestete (blind portierte) Treiber setzen `isTested = false`.
protocol ScaleDriver {
    var displayName: String { get }
    var isTested: Bool { get }
    var kind: ScaleConnectionKind { get }

    /// Erkennt dieses Gerät anhand Name / Advertisement-Daten / beworbener Dienste.
    func matches(name: String?, serviceData: [CBUUID: Data], advertised: [CBUUID]) -> Bool

    /// Nur `.advertisement`: liest eine Messung aus den Servicedaten.
    func parse(serviceData: [CBUUID: Data], localName: String?) -> ScaleReading?

    /// Nur `.connection`: welche Dienste/Characteristics abonniert werden.
    var connectionProfile: ConnectionProfile? { get }

    /// Nur `.connection`: verarbeitet Notification-Daten einer Characteristic.
    func handle(characteristic uuid: CBUUID, data: Data) -> ScaleReading?
}

// Standard-Implementierungen, damit jeder Treiber nur das Nötige umsetzt.
extension ScaleDriver {
    func parse(serviceData: [CBUUID: Data], localName: String?) -> ScaleReading? { nil }
    var connectionProfile: ConnectionProfile? { nil }
    func handle(characteristic uuid: CBUUID, data: Data) -> ScaleReading? { nil }
}

/// Registry aller bekannten Treiber. Hier neue Waagen eintragen.
/// Reihenfolge: Advertisement-Treiber zuerst, dann Verbindungs-Treiber.
enum ScaleDriverRegistry {
    static let all: [ScaleDriver] = [
        MiBodyCompositionScale2Driver(),   // getestet-Ziel, aktuell noch zu kalibrieren
        MiSmartScaleV1Driver(),            // experimentell (Advertisement, nur Gewicht)
        GenericSIGScaleDriver(),           // experimentell (Verbindung, Bluetooth-SIG-Norm)
    ]
}
