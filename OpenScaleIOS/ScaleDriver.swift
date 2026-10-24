// SPDX-License-Identifier: GPL-3.0-or-later
//
// OpenTara – lokale Körperwaagen-App
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
    /// Zeitpunkt der Messung laut Waage (z. B. aus einem Zeitstempel im Protokoll).
    /// `nil` = jetzt. Treiber ohne eigene Uhr lassen das Feld weg.
    var date: Date? = nil
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
    /// Characteristic, auf die der Treiber schreibt (Kommando/Quittungs-Protokolle wie
    /// Beurer/Sanitas). `nil` = reiner Lese-Treiber, `ScaleDriverLink.send` tut dann nichts.
    let writeUUID: CBUUID?

    init(serviceUUIDs: [CBUUID], notifyUUIDs: [CBUUID], writeUUID: CBUUID? = nil) {
        self.serviceUUIDs = serviceUUIDs
        self.notifyUUIDs = notifyUUIDs
        self.writeUUID = writeUUID
    }
}

/// Was ein Treiber über die Person wissen darf, die sich wiegt. Nur Waagen mit eigener
/// Nutzerverwaltung (Beurer/Sanitas) brauchen das; sie legen damit einen Nutzer auf der
/// Waage an oder erkennen ihn wieder.
struct ScaleUserContext {
    var name: String
    var birthDate: Date
    var heightCm: Double
    var sex: Sex
    /// Aktivitätslevel 1 (wenig) … 5 (sehr aktiv). OpenTara pflegt keins, Standard 3.
    var activityLevel: Int = 3
    var weightUnit: WeightUnit = .kg
}

extension ScaleUserContext {
    init(profile: UserProfile, unit: WeightUnit) {
        self.init(name: profile.name, birthDate: profile.birthDate, heightCm: profile.heightCm,
                  sex: profile.sex, weightUnit: unit)
    }
}

/// Rückkanal vom Verbindungs-Treiber zur App: Bytes an die Waage schreiben, in die
/// Rohdaten-Karte loggen, Statuszeile setzen. Der `ScaleManager` baut ihn, sobald die
/// Notifications aktiv sind und (falls `writeUUID` gesetzt) die Schreib-Characteristic
/// gefunden wurde.
struct ScaleDriverLink {
    let user: ScaleUserContext?
    /// Schreibt an `connectionProfile.writeUUID` (withResponse, wenn die Characteristic es kann).
    let send: (Data) -> Void
    /// Eine Zeile in die Rohdaten-Karte.
    let log: (String) -> Void
    /// Statuszeile oben in der App (lokalisiert übergeben).
    let status: (String) -> Void
}

/// Schnittstelle für einen Waagen-Treiber. Pro Modell eine Implementierung.
/// Ungetestete (blind portierte) Treiber setzen `isTested = false`.
///
/// Reine Lese-Treiber (Advertisement oder nur Notifications) brauchen nur die Pflicht-
/// Methoden; Treiber mit Kommando/Quittungs-Protokoll setzen zusätzlich `writeUUID`,
/// `onReady(_:)`, `handle(characteristic:data:link:)` und `onDisconnected()` um.
/// Solche Treiber halten Zustand und sind deshalb Klassen (der Manager verbindet
/// immer nur eine Waage zugleich).
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

    /// Nur `.connection`: Notifications sind aktiv, der Treiber darf jetzt senden.
    /// Wird einmal pro Verbindung aufgerufen.
    func onReady(_ link: ScaleDriverLink)

    /// Nur `.connection`: Notification mit Rückkanal (Quittungen, nächstes Kommando).
    /// Standard: delegiert an `handle(characteristic:data:)`.
    func handle(characteristic uuid: CBUUID, data: Data, link: ScaleDriverLink) -> ScaleReading?

    /// Nur `.connection`: Verbindung beendet oder abgebrochen – Zustand verwerfen.
    func onDisconnected()
}

// Standard-Implementierungen, damit jeder Treiber nur das Nötige umsetzt.
extension ScaleDriver {
    func parse(serviceData: [CBUUID: Data], localName: String?) -> ScaleReading? { nil }
    var connectionProfile: ConnectionProfile? { nil }
    func handle(characteristic uuid: CBUUID, data: Data) -> ScaleReading? { nil }
    func onReady(_ link: ScaleDriverLink) {}
    func handle(characteristic uuid: CBUUID, data: Data, link: ScaleDriverLink) -> ScaleReading? {
        handle(characteristic: uuid, data: data)
    }
    func onDisconnected() {}
}

/// Registry aller bekannten Treiber. Hier neue Waagen eintragen.
/// Reihenfolge: Advertisement-Treiber zuerst, dann Verbindungs-Treiber.
enum ScaleDriverRegistry {
    static let all: [ScaleDriver] = [
        MiBodyCompositionScale2Driver(),   // getestet-Ziel, aktuell noch zu kalibrieren
        MiSmartScaleV1Driver(),            // experimentell (Advertisement, nur Gewicht)
        BeurerSanitasDriver(),             // experimentell (Verbindung, Beurer/Sanitas-Protokoll, erkennt per Name)
        GenericSIGScaleDriver(),           // experimentell (Verbindung, Bluetooth-SIG-Norm)
    ]
}
