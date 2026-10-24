// SPDX-License-Identifier: GPL-3.0-or-later
//
// OpenTara – lokale Körperwaagen-App
// Protokoll aus openScale (GPLv3, oliexdev/openScale) portiert:
//   android_app/app/src/main/java/com/health/openscale/core/bluetooth/scales/BeurerSanitasHandler.kt
//   Wiki: https://github.com/oliexdev/openScale/wiki/Beurer-Sanitas

import Foundation
import CoreBluetooth

// MARK: - Byte-Logik (ohne Bluetooth, in Unit-Tests prüfbar)

/// Beurer/Sanitas-Protokoll: ein Dienst 0xFFE0, eine Characteristic 0xFFE1 für Schreiben
/// und Notifications. Jeder Frame beginnt mit einem modellabhängigen Startbyte (0xE7 oder
/// 0xF7); Init, Uhrzeit und Trennen nutzen ein "alternatives Startbyte" mit anderem
/// Low-Nibble (0xE6/0xE9/0xEA bzw. 0xF6/0xF9/0xFA). Die Waage quittiert Kommandos mit
/// `<sb> F0 <cmd> …`, die App quittiert Datenframes mit `<sb> F1 <cmd> <count> <current>`.
enum BeurerSanitasProtocol {

    static let serviceUUID = CBUUID(string: "FFE0")
    static let characteristicUUID = CBUUID(string: "FFE1")

    enum Model: CaseIterable {
        case beurerBF700_800_RTLibra   // Beurer BF700, BF800, Runtastic Libra – Startbyte 0xF7
        case beurerBF710               // Beurer BF710 – Startbyte 0xE7
        case sanitasSBF70_75           // Sanitas SBF70, SilverCrest SBF75, Crane – Startbyte 0xE7

        var startByte: UInt8 {
            switch self {
            case .beurerBF700_800_RTLibra: return 0xF7
            case .beurerBF710, .sanitasSBF70_75: return 0xE7
            }
        }

        var displayName: String {
            switch self {
            case .beurerBF700_800_RTLibra: return "Beurer BF700/BF800 / Runtastic Libra"
            case .beurerBF710: return "Beurer BF710"
            case .sanitasSBF70_75: return "Sanitas SBF70 / SilverCrest SBF75 / Crane"
            }
        }
    }

    /// Modellerkennung nach BLE-Namen – Reihenfolge und Muster wie `supportFor()` in
    /// openScale (dort `contains`, case-insensitive). Die Reihenfolge ist wichtig:
    /// "BEURER BF700" trifft zuerst die BF700/800-Familie, ein nackter Name "BF700"
    /// meldet sich laut openScale als BF710.
    static func model(forName name: String?) -> Model? {
        guard let name, !name.isEmpty else { return nil }
        let n = name.lowercased()
        let bf700Family = ["bf-700", "beurer bf700", "bf-800", "beurer bf800",
                           "rt-libra-b", "rt-libra-w", "libra-b", "libra-w"]
        if bf700Family.contains(where: { n.contains($0) }) { return .beurerBF700_800_RTLibra }
        if n.contains("bf700") || n.contains("beurer bf710") { return .beurerBF710 }
        if n.contains("sanitas sbf70") || n.contains("sbf75") || n.contains("aicdscale1") {
            return .sanitasSBF70_75
        }
        return nil
    }

    // Low-Nibble der alternativen Startbytes
    static let nibbleInit: UInt8 = 0x6
    static let nibbleCommand: UInt8 = 0x7
    static let nibbleSetTime: UInt8 = 0x9
    static let nibbleDisconnect: UInt8 = 0xA

    enum Cmd {
        static let userAdd: UInt8 = 0x31
        static let userDelete: UInt8 = 0x32
        static let userList: UInt8 = 0x33
        static let userInfo: UInt8 = 0x34          // eine Zeile der Nutzerliste
        static let userUpdate: UInt8 = 0x35
        static let userDetails: UInt8 = 0x36
        static let doMeasurement: UInt8 = 0x40
        static let getSavedMeasurements: UInt8 = 0x41
        static let savedMeasurement: UInt8 = 0x42
        static let deleteSavedMeasurements: UInt8 = 0x43
        static let setUnit: UInt8 = 0x4D
        static let setThreshold: UInt8 = 0x4E
        static let scaleStatus: UInt8 = 0x4F
        static let weightMeasurement: UInt8 = 0x58  // Live-Gewicht während der Messung
        static let measurement: UInt8 = 0x59        // fertige Messung in Teilen
        static let scaleAck: UInt8 = 0xF0
        static let appAck: UInt8 = 0xF1
    }

    /// Alternatives Startbyte: High-Nibble des Startbytes, Low-Nibble aus `nibble`.
    static func altStartByte(_ startByte: UInt8, nibble: UInt8) -> UInt8 {
        (startByte & 0xF0) | (nibble & 0x0F)
    }

    /// Startbyte-Familie wechseln (0xE7 ↔ 0xF7) – Fallback, wenn die Waage auf Init nicht antwortet.
    static func otherFamily(_ startByte: UInt8) -> UInt8 {
        ((startByte & 0xF0) == 0xE0 ? 0xF0 : 0xE0) | (startByte & 0x0F)
    }

    /// `<alt sb 6> 01`
    static func initCommand(startByte: UInt8) -> [UInt8] {
        [altStartByte(startByte, nibble: nibbleInit), 0x01]
    }

    /// `<alt sb 9> <unix-timestamp 4 Byte BE>`
    static func setTimeCommand(startByte: UInt8, date: Date) -> [UInt8] {
        let ts = UInt32(clamping: Int64(date.timeIntervalSince1970))
        return [altStartByte(startByte, nibble: nibbleSetTime)] + be32(ts)
    }

    /// `<alt sb A> 02`
    static func disconnectCommand(startByte: UInt8) -> [UInt8] {
        [altStartByte(startByte, nibble: nibbleDisconnect), 0x02]
    }

    /// `<sb> <cmd> <payload…>`
    static func command(startByte: UInt8, _ cmd: UInt8, payload: [UInt8] = []) -> [UInt8] {
        [startByte, cmd] + payload
    }

    /// App-Quittung für einen Datenframe: `<sb> F1` + Bytes 1…3 des Frames (cmd, count, current).
    static func ack(startByte: UInt8, for frame: [UInt8]) -> [UInt8] {
        [startByte, Cmd.appAck] + Array(frame.dropFirst().prefix(3))
    }

    static func encodeUserId(_ uid: UInt64) -> [UInt8] {
        be32(UInt32(truncatingIfNeeded: uid >> 32)) + be32(UInt32(truncatingIfNeeded: uid))
    }

    static func decodeUserId(_ b: [UInt8], at offset: Int) -> UInt64? {
        guard b.count >= offset + 8 else { return nil }
        return b[offset..<offset + 8].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    static func unitCode(for unit: WeightUnit) -> UInt8 {
        switch unit {
        case .kg: return 1
        case .lb: return 2
        case .st: return 4
        }
    }

    /// Nutzername, wie ihn die Waage speichert: ohne Akzente, nur A–Z/0–9, Großbuchstaben.
    /// Die Waage selbst kennt nur die ersten 3 Zeichen. Leerer Name → "OT" (OpenTara).
    static func scaleName(for name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
        var kept = ""
        for scalar in folded.unicodeScalars where scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) {
            kept.unicodeScalars.append(scalar)
        }
        let s = kept.uppercased()
        return s.isEmpty ? "OT" : s
    }

    /// Die 3 Byte, die im Nutzerdatensatz der Waage stehen (mit 0 aufgefüllt).
    static func nameBytes(_ scaleName: String) -> [UInt8] {
        var b = Array(scaleName.utf8.prefix(3))
        while b.count < 3 { b.append(0) }
        return b
    }

    static func decodeName(_ b: [UInt8], at offset: Int, maxLength: Int = 3) -> String {
        var bytes: [UInt8] = []
        var i = offset
        while i < b.count, bytes.count < maxLength, b[i] != 0 { bytes.append(b[i]); i += 1 }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Nutzerdatensatz, wie ihn `<sb> 31` (anlegen) und `<sb> 35` (ändern) erwarten.
    struct UserRecord: Equatable {
        var uid: UInt64
        var name: String        // bereits per `scaleName(for:)` normalisiert, max. 3 Zeichen relevant
        var birthYear: Int
        var birthMonth: Int     // 1…12
        var birthDay: Int
        var heightCm: Int
        var isMale: Bool
        var activityLevel: Int  // 1…5
    }

    static func userRecord(from user: ScaleUserContext, uid: UInt64, calendar: Calendar) -> UserRecord {
        let c = calendar.dateComponents([.year, .month, .day], from: user.birthDate)
        return UserRecord(uid: uid,
                          name: scaleName(for: user.name),
                          birthYear: c.year ?? 1990,
                          birthMonth: c.month ?? 1,
                          birthDay: c.day ?? 1,
                          heightCm: Int(user.heightCm.rounded()),
                          isMale: user.sex == .male,
                          activityLevel: min(max(user.activityLevel, 1), 5))
    }

    /// `<sb> 31 <uid 8> <name 3> <year-1900> <month 0-basiert> <day> <height cm> <sex|activity>`
    static func addUserCommand(startByte: UInt8, user: UserRecord) -> [UInt8] {
        let yearByte = UInt8(clamping: user.birthYear - 1900)
        let monthByte = UInt8(clamping: user.birthMonth - 1)
        let dayByte = UInt8(clamping: user.birthDay)
        let heightByte = UInt8(clamping: user.heightCm)
        let sexActivity: UInt8 = (user.isMale ? 0x80 : 0x00) | UInt8(clamping: user.activityLevel) & 0x0F
        let payload = encodeUserId(user.uid) + nameBytes(user.name)
            + [yearByte, monthByte, dayByte, heightByte, sexActivity]
        return command(startByte: startByte, Cmd.userAdd, payload: payload)
    }

    /// Antwort auf `<sb> 4F`: `<sb> F0 4F <??> <battery> <wthr> <fthr> <unit> <ue> <urwe> <ume> <version>`
    struct Status: Equatable {
        var batteryPercent: Int
        var weightThresholdKg: Double   // Einheit 100 g
        var fatThresholdPercent: Double // Einheit 0,1 %
        var unitCode: Int               // 1 kg, 2 lb, 4 st
        var userExists: Bool
        var userReferenceWeightExists: Bool
        var userMeasurementExists: Bool
        var version: Int
    }

    static func parseStatus(_ f: [UInt8]) -> Status? {
        guard f.count >= 12, f[1] == Cmd.scaleAck, f[2] == Cmd.scaleStatus else { return nil }
        return Status(batteryPercent: Int(f[4]),
                      weightThresholdKg: Double(f[5]) / 10.0,
                      fatThresholdPercent: Double(f[6]) / 10.0,
                      unitCode: Int(f[7]),
                      userExists: f[8] == 0,
                      userReferenceWeightExists: f[9] == 0,
                      userMeasurementExists: f[10] == 0,
                      version: Int(f[11]))
    }

    /// Eine Zeile der Nutzerliste: `<sb> 34 <count> <current> <uid 8> <name 3> <year-1900>`
    struct UserListEntry: Equatable {
        var count: Int
        var current: Int
        var uid: UInt64
        var name: String
        var birthYear: Int
    }

    static func parseUserListEntry(_ f: [UInt8]) -> UserListEntry? {
        guard f.count >= 16, f[1] == Cmd.userInfo, let uid = decodeUserId(f, at: 4) else { return nil }
        return UserListEntry(count: Int(f[2]), current: Int(f[3]), uid: uid,
                             name: decodeName(f, at: 12), birthYear: 1900 + Int(f[15]))
    }

    /// Antwort auf `<sb> 36 <uid>`: `<sb> F0 36 00 <name 3> <year> <month> <day> <height> <sex|activity>`
    static func parseUserDetails(_ f: [UInt8]) -> UserRecord? {
        guard f.count >= 12, f[1] == Cmd.scaleAck, f[2] == Cmd.userDetails, f[3] == 0 else { return nil }
        return UserRecord(uid: 0, name: decodeName(f, at: 4), birthYear: 1900 + Int(f[7]),
                          birthMonth: 1 + Int(f[8]), birthDay: Int(f[9]), heightCm: Int(f[10]),
                          isMale: (f[11] & 0xF0) != 0, activityLevel: Int(f[11] & 0x0F))
    }

    /// Live-Gewicht während der Messung: `<sb> 58 <status> <weight 2 BE, 50 g>`; status 0 = stabil.
    struct LiveWeight: Equatable {
        var isStable: Bool
        var weightKg: Double
    }

    static func parseLiveWeight(_ f: [UInt8]) -> LiveWeight? {
        guard f.count >= 5, f[1] == Cmd.weightMeasurement else { return nil }
        return LiveWeight(isStable: f[2] == 0, weightKg: kilograms(f, at: 3))
    }

    /// Fertige Messung, 22 Byte aus den `<sb> 59`-Teilen zusammengesetzt:
    /// `<timestamp 4> <weight 2> <impedance 2> <fat 2> <water 2> <muscle 2> <bone 2> <BMR 2> <AMR 2> <BMI 2>`
    struct Measurement: Equatable {
        var timestamp: UInt32       // Unix-Sekunden, Bit 31 bereits ausmaskiert
        var weightKg: Double
        var impedanceOhm: Int
        var fatPercent: Double
        var waterPercent: Double
        var musclePercent: Double
        /// Knochenmasse in 50-g-Schritten wie in openScale gelesen. Auf einem BF700 kam am
        /// 24.10.2026 der Rohwert 288 (= 14,40 kg so gelesen, 2,88 kg bei 10 g) – die Einheit ist
        /// noch nicht gegen das Display der Waage bestätigt, deshalb steht `boneRaw` daneben.
        var boneKg: Double
        var boneRaw: Int
        var bmrKcal: Int
        var amrKcal: Int
        var bmi: Double

        var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }
    }

    static let measurementLength = 22

    static func parseMeasurement(_ b: [UInt8]) -> Measurement? {
        guard b.count >= measurementLength else { return nil }
        // Manche Firmwares setzen Bit 31 im Zeitstempel der Live-Messung (openScale #1500,
        // BF800-W: 0xEA9290C2 statt 0x6A9290C2). Bis 2038 braucht kein Unix-Zeitstempel Bit 31.
        let ts = u32(b, at: 0) & 0x7FFF_FFFF
        return Measurement(timestamp: ts,
                           weightKg: kilograms(b, at: 4),
                           impedanceOhm: Int(u16(b, at: 6)),
                           fatPercent: Double(u16(b, at: 8)) / 10.0,
                           waterPercent: Double(u16(b, at: 10)) / 10.0,
                           musclePercent: Double(u16(b, at: 12)) / 10.0,
                           boneKg: kilograms(b, at: 14),
                           boneRaw: Int(u16(b, at: 14)),
                           bmrKcal: Int(u16(b, at: 16)),
                           amrKcal: Int(u16(b, at: 18)),
                           bmi: Double(u16(b, at: 20)) / 10.0)
    }

    // Hilfen

    static func hex(_ b: [UInt8]) -> String {
        b.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private static func be32(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    private static func u16(_ b: [UInt8], at i: Int) -> UInt16 {
        (UInt16(b[i]) << 8) | UInt16(b[i + 1])
    }

    private static func u32(_ b: [UInt8], at i: Int) -> UInt32 {
        (UInt32(b[i]) << 24) | (UInt32(b[i + 1]) << 16) | (UInt32(b[i + 2]) << 8) | UInt32(b[i + 3])
    }

    /// 2 Byte BE in 50-g-Schritten.
    private static func kilograms(_ b: [UInt8], at i: Int) -> Double {
        Double(u16(b, at: i)) * 50.0 / 1000.0
    }
}

// MARK: - Treiber (Zustandsmaschine)

/// Beurer BF700 / BF710 / BF800 / Runtastic Libra, Sanitas SBF70, SilverCrest SBF75, Crane.
///
/// EXPERIMENTELL: blind aus openScale portiert, noch nicht mit Hardware verifiziert.
///
/// Ablauf pro Verbindung (wie `proceedTo()` in openScale, verkürzt):
///  1. Init `<alt sb 6> 01` → Quittung `<alt sb 6> 00 20`
///  2. Uhrzeit setzen, Status abfragen (Batterie, Einheit, Version); Einheit ggf. angleichen
///  3. Nutzerliste holen, jede Zeile quittieren
///  4. Nutzer aus dem OpenTara-Profil wiedererkennen (3-Zeichen-Name + Geburtsjahr) oder anlegen
///  5. Nutzerdetails abfragen (nur Log), Messung starten `<sb> 40 <uid>`
///  6. Live-Gewicht `<sb> 58` anzeigen, fertige Messung aus den `<sb> 59`-Teilen zusammensetzen
///
/// Nicht portiert (Folgearbeit): auf der Waage gespeicherte Messungen (0x41/0x42/0x43) und
/// "unbekannte" Messungen (0x46/0x47/0x4B) abholen. Der Treiber löscht nie etwas auf der Waage.
final class BeurerSanitasDriver: ScaleDriver {
    typealias P = BeurerSanitasProtocol

    let isTested = false
    let kind = ScaleConnectionKind.connection
    var displayName: String { model?.displayName ?? "Beurer BF700/710/800 · Sanitas SBF70/75" }

    enum Step: Equatable {
        case idle
        case initialize
        case status
        case setUnit
        case userList
        case ensureUser
        case userDetails
        case measure
        case measuring
        case finished
    }

    struct RemoteUser: Equatable {
        var uid: UInt64
        var name: String
        var birthYear: Int
    }

    // Zustand der aktuellen Verbindung
    private(set) var model: P.Model?
    private(set) var startByte: UInt8 = 0xE7
    private(set) var step: Step = .idle
    private(set) var remoteUsers: [RemoteUser] = []
    private(set) var currentUser: RemoteUser?
    private var link: ScaleDriverLink?
    private var partialMeasurement: [UInt8]?
    private var initRetried = false
    private var timeoutToken = 0

    // Für Tests ersetzbar
    var now: () -> Date = { Date() }
    var calendar = Calendar.current
    var scheduleTimeout: (TimeInterval, @escaping () -> Void) -> Void = { seconds, action in
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
    }

    // MARK: ScaleDriver

    func matches(name: String?, serviceData: [CBUUID: Data], advertised: [CBUUID]) -> Bool {
        guard let m = P.model(forName: name) else { return false }
        model = m
        return true
    }

    var connectionProfile: ConnectionProfile? {
        ConnectionProfile(serviceUUIDs: [P.serviceUUID],
                          notifyUUIDs: [P.characteristicUUID],
                          writeUUID: P.characteristicUUID)
    }

    func onReady(_ link: ScaleDriverLink) {
        self.link = link
        startByte = (model ?? .beurerBF710).startByte
        remoteUsers = []
        currentUser = nil
        partialMeasurement = nil
        initRetried = false
        log("Beurer/Sanitas: \(displayName), Startbyte \(hexByte(startByte))")
        proceed(to: .initialize)
    }

    func onDisconnected() {
        cancelTimeout()
        link = nil
        step = .idle
        partialMeasurement = nil
    }

    func handle(characteristic uuid: CBUUID, data: Data, link: ScaleDriverLink) -> ScaleReading? {
        guard uuid == P.characteristicUUID else { return nil }
        self.link = link
        let f = [UInt8](data)
        guard f.count >= 2 else { return nil }

        // Init-Quittung kommt mit alternativem Startbyte (Low-Nibble 6). Antwortet die Waage
        // mit der anderen Familie (0xF6 statt 0xE6), übernehmen wir deren Startbyte.
        if (f[0] & 0x0F) == P.nibbleInit, f.count >= 3, f[1] == 0x00 {
            startByte = (f[0] & 0xF0) | P.nibbleCommand
            log("← Init-Quittung, Startbyte \(hexByte(startByte))")
            proceed(to: .status)
            return nil
        }

        guard f[0] == startByte else {
            log("← unerwartetes Startbyte \(hexByte(f[0])) (erwartet \(hexByte(startByte))) – ignoriert")
            return nil
        }

        switch f[1] {
        case P.Cmd.userInfo:
            handleUserListEntry(f)
            return nil
        case P.Cmd.weightMeasurement:
            return handleLiveWeight(f)
        case P.Cmd.measurement:
            return handleMeasurementPart(f)
        case P.Cmd.savedMeasurement:
            // Wird nicht angefordert; falls die Waage trotzdem sendet: quittieren, nicht auswerten.
            send(P.ack(startByte: startByte, for: f))
            log("← gespeicherte Messung (Teil \(f.count > 3 ? Int(f[3]) : 0)) – nicht ausgewertet")
            return nil
        case P.Cmd.scaleAck:
            handleScaleAck(f)
            return nil
        default:
            log("← unbekanntes Kommando \(hexByte(f[1]))")
            return nil
        }
    }

    // MARK: Schrittsteuerung

    private func proceed(to next: Step) {
        step = next
        cancelTimeout()
        switch next {
        case .idle, .finished:
            break

        case .initialize:
            log("→ Init")
            send(P.initCommand(startByte: startByte))
            armTimeout(3) { [weak self] in self?.initTimedOut() }

        case .status:
            log("→ Uhrzeit setzen, Status abfragen")
            send(P.setTimeCommand(startByte: startByte, date: now()))
            send(P.command(startByte: startByte, P.Cmd.scaleStatus, payload: P.encodeUserId(0)))
            armStepTimeout()

        case .setUnit:
            armStepTimeout()

        case .userList:
            log("→ Nutzerliste")
            send(P.command(startByte: startByte, P.Cmd.userList))
            armStepTimeout()

        case .ensureUser:
            ensureUser()

        case .userDetails:
            guard let u = currentUser else { proceed(to: .measure); return }
            log("→ Nutzerdetails \(u.name)")
            send(P.command(startByte: startByte, P.Cmd.userDetails, payload: P.encodeUserId(u.uid)))
            // Nur Diagnose: antwortet die Waage nicht, trotzdem messen.
            armTimeout(10) { [weak self] in
                self?.log("keine Nutzerdetails – messe trotzdem")
                self?.proceed(to: .measure)
            }

        case .measure:
            guard let u = currentUser else {
                status(String(localized: "Kein Nutzer auf der Waage – Messung nicht möglich"))
                step = .finished
                return
            }
            log("→ Messung starten für \(u.name) (uid \(u.uid))")
            send(P.command(startByte: startByte, P.Cmd.doMeasurement, payload: P.encodeUserId(u.uid)))
            armStepTimeout()

        case .measuring:
            status(String(localized: "Jetzt barfuß auf die Waage stellen"))
            armTimeout(120) { [weak self] in
                self?.log("keine Messung innerhalb von 2 Minuten")
            }
        }
    }

    private func ensureUser() {
        guard let user = link?.user else {
            status(String(localized: "Kein Profil gewählt – Messung nicht möglich"))
            step = .finished
            return
        }
        let localName = P.scaleName(for: user.name)
        let birthYear = calendar.component(.year, from: user.birthDate)

        // Wiedererkennen über Name-Präfix (die Waage speichert 3 Zeichen, die Hersteller-App
        // teils in Kleinbuchstaben) und Geburtsjahr – wie openScale.
        let sameName = remoteUsers.filter { !$0.name.isEmpty && localName.lowercased().hasPrefix($0.name.lowercased()) }
        if let known = sameName.first(where: { $0.birthYear == birthYear }) {
            currentUser = known
            log("Nutzer wiedererkannt: \(known.name) (\(known.birthYear), uid \(known.uid))")
            proceed(to: .userDetails)
            return
        }
        // Gleicher Name, anderes Geburtsjahr (z. B. in der Hersteller-App anders eingetragen):
        // die Waage lehnt einen zweiten Nutzer mit diesem Namen ab (Code 3), also den vorhandenen
        // nehmen. Die Körperwerte rechnet OpenTara ohnehin selbst aus Gewicht und Impedanz.
        if sameName.count == 1, let known = sameName.first {
            currentUser = known
            log("Nutzer \(known.name) auf der Waage hat Geburtsjahr \(known.birthYear), Profil \(birthYear) – nutze ihn trotzdem (uid \(known.uid))")
            proceed(to: .userDetails)
            return
        }

        // Neu anlegen: uid = max(vorhandene) + 1, mindestens 101 (wie openScale).
        let maxUid = remoteUsers.map(\.uid).max() ?? 100
        let record = P.userRecord(from: user, uid: maxUid + 1, calendar: calendar)
        currentUser = RemoteUser(uid: record.uid,
                                 name: String(decoding: P.nameBytes(record.name).filter { $0 != 0 }, as: UTF8.self),
                                 birthYear: record.birthYear)
        let shortName = String(record.name.prefix(3))
        let sex = record.isMale ? "m" : "w"
        log("→ Nutzer anlegen: \(shortName) \(record.birthYear)-\(record.birthMonth)-\(record.birthDay), \(record.heightCm) cm, \(sex), Aktivität \(record.activityLevel), uid \(record.uid)")
        send(P.addUserCommand(startByte: startByte, user: record))
        armStepTimeout()
    }

    // MARK: Eingehende Frames

    private func handleScaleAck(_ f: [UInt8]) {
        guard f.count >= 3 else { return }
        cancelTimeout()
        switch f[2] {
        case P.Cmd.scaleStatus:
            guard let s = P.parseStatus(f) else { log("← Status: zu kurz"); return }
            log("← Status: Batterie \(s.batteryPercent) %, Einheit \(s.unitCode), Version \(s.version), Schwellen \(s.weightThresholdKg) kg / \(s.fatThresholdPercent) %")
            if s.batteryPercent <= 10 {
                status(String(localized: "Waage: Batterie fast leer (\(s.batteryPercent) %%)"))
            }
            let wanted = P.unitCode(for: link?.user?.weightUnit ?? .kg)
            if Int(wanted) != s.unitCode {
                log("→ Einheit auf \(wanted) stellen")
                step = .setUnit
                send(P.command(startByte: startByte, P.Cmd.setUnit, payload: [wanted]))
                armStepTimeout()
            } else {
                proceed(to: .userList)
            }

        case P.Cmd.setUnit:
            log(f.count > 3 && f[3] == 0 ? "← Einheit gesetzt" : "← Einheit nicht gesetzt")
            proceed(to: .userList)

        case P.Cmd.userList:
            let count = f.count > 4 ? Int(f[4]) : 0
            let maxUsers = f.count > 5 ? Int(f[5]) : 0
            log("← Nutzerliste: \(count) von max. \(maxUsers)")
            if count == 0 {
                proceed(to: .ensureUser)
            } else {
                armStepTimeout()   // jetzt kommen die 0x34-Zeilen
            }

        case P.Cmd.userAdd:
            let code = f.count > 3 ? Int(f[3]) : -1
            switch code {
            case 0:
                log("← Nutzer angelegt")
                if let u = currentUser { remoteUsers.append(u) }
                proceed(to: .measure)
            case 1:
                status(String(localized: "Waage: Nutzerspeicher voll – bitte in der Hersteller-App einen Nutzer löschen"))
                currentUser = nil
                step = .finished
            case 3:
                // Name schon vergeben: den vorhandenen Nutzer mit diesem Namen verwenden.
                let name = currentUser?.name.lowercased() ?? ""
                if let existing = remoteUsers.first(where: { !name.isEmpty && $0.name.lowercased() == name }) {
                    log("← Name \(existing.name) schon vergeben – nutze vorhandenen Nutzer (uid \(existing.uid), \(existing.birthYear))")
                    currentUser = existing
                    proceed(to: .userDetails)
                } else {
                    log("← Nutzer anlegen abgelehnt: Name schon vergeben")
                    status(String(localized: "Waage hat den Nutzer abgelehnt (Name schon vergeben)"))
                    currentUser = nil
                    step = .finished
                }
            default:
                log("← Nutzer anlegen abgelehnt (Code \(code))")
                status(String(localized: "Waage hat den Nutzer abgelehnt (Code \(code))"))
                currentUser = nil
                step = .finished
            }

        case P.Cmd.userDetails:
            if let d = P.parseUserDetails(f) {
                let sex = d.isMale ? "m" : "w"
                log("← Nutzerdetails: \(d.name) \(d.birthYear)-\(d.birthMonth)-\(d.birthDay), \(d.heightCm) cm, \(sex), Aktivität \(d.activityLevel)")
            } else {
                log("← Nutzerdetails: Fehler")
            }
            proceed(to: .measure)

        case P.Cmd.doMeasurement:
            if f.count > 3, f[3] == 0 {
                log("← Messung freigegeben")
                proceed(to: .measuring)
            } else {
                log("← Messung abgelehnt")
                status(String(localized: "Waage hat die Messung abgelehnt"))
                step = .finished
            }

        case P.Cmd.getSavedMeasurements, P.Cmd.deleteSavedMeasurements:
            log("← Quittung \(hexByte(f[2])) (nicht angefordert)")

        default:
            log("← Quittung für \(hexByte(f[2]))")
        }
    }

    private func handleUserListEntry(_ f: [UInt8]) {
        guard let e = P.parseUserListEntry(f) else {
            log("← Nutzerzeile: zu kurz")
            return
        }
        if remoteUsers.count == e.current - 1 {
            remoteUsers.append(RemoteUser(uid: e.uid, name: e.name, birthYear: e.birthYear))
        }
        log("← Nutzer \(e.current)/\(e.count): \(e.name) (\(e.birthYear), uid \(e.uid))")
        send(P.ack(startByte: startByte, for: f))
        if e.current >= e.count {
            proceed(to: .ensureUser)
        } else {
            armStepTimeout()
        }
    }

    private func handleLiveWeight(_ f: [UInt8]) -> ScaleReading? {
        guard let w = P.parseLiveWeight(f) else { return nil }
        send(P.ack(startByte: startByte, for: f))
        if w.isStable {
            log(String(format: "← Gewicht stabil %.2f kg – warte auf Körperwerte", w.weightKg))
            armTimeout(30) { [weak self] in self?.log("keine Körperwerte nach stabilem Gewicht") }
        } else {
            armTimeout(120) { [weak self] in self?.log("Messung nicht abgeschlossen") }
        }
        // Stabiles Gewicht sofort als Messung melden; die vollständige Messung (mit Impedanz)
        // folgt Sekunden später und aktualisiert denselben Eintrag.
        return ScaleReading(weightKg: w.weightKg, impedance: nil, isStabilized: w.isStable,
                            weightRemoved: false, rawHex: P.hex(f), source: displayName)
    }

    private func handleMeasurementPart(_ f: [UInt8]) -> ScaleReading? {
        guard f.count >= 4 else { return nil }
        let count = Int(f[2])
        let current = Int(f[3])

        if current == 1 {
            // Kopf: `<sb> 59 <count> 01 01 <uid 8>`
            partialMeasurement = nil
            if let uid = P.decodeUserId(f, at: 5) {
                let who = remoteUsers.first { $0.uid == uid }?.name ?? "unbekannt"
                log("← Messung 1/\(count) für uid \(uid) (\(who))")
            } else {
                log("← Messung 1/\(count)")
            }
        } else {
            let part = Array(f.dropFirst(4))
            if current == 2 || partialMeasurement == nil {
                partialMeasurement = part
            } else {
                partialMeasurement! += part
            }
            log("← Messung \(current)/\(count): \(part.count) Byte")
        }
        send(P.ack(startByte: startByte, for: f))

        guard current >= count else {
            armTimeout(10) { [weak self] in self?.log("Messung unvollständig geblieben") }
            return nil
        }

        cancelTimeout()
        step = .finished
        guard let bytes = partialMeasurement, let m = P.parseMeasurement(bytes) else {
            log("Messung unvollständig: \(partialMeasurement?.count ?? 0) Byte statt \(P.measurementLength)")
            status(String(localized: "Messung unvollständig empfangen"))
            return nil
        }
        partialMeasurement = nil
        log(String(format: "Waage meldet: %.2f kg, %ld Ω, Fett %.1f %%, Wasser %.1f %%, Muskel %.1f %%, Knochen roh %ld (%.2f kg bei 10 g, %.2f kg bei 50 g), BMR %ld, AMR %ld, BMI %.1f",
                   m.weightKg, m.impedanceOhm, m.fatPercent, m.waterPercent, m.musclePercent,
                   m.boneRaw, Double(m.boneRaw) / 100.0, m.boneKg, m.bmrKcal, m.amrKcal, m.bmi))
        status(String(localized: "Messung abgeschlossen"))

        // Zeitstempel der Waage nur übernehmen, wenn er plausibel ist (±1 Tag), sonst "jetzt".
        let date = abs(m.date.timeIntervalSince(now())) < 86_400 ? m.date : nil
        return ScaleReading(weightKg: m.weightKg,
                            impedance: m.impedanceOhm > 0 ? m.impedanceOhm : nil,
                            isStabilized: true, weightRemoved: false,
                            rawHex: P.hex(bytes), source: displayName, date: date)
    }

    // MARK: Timeouts

    private func initTimedOut() {
        guard step == .initialize else { return }
        if initRetried {
            log("Waage antwortet nicht auf Init")
            status(String(localized: "Waage antwortet nicht"))
            step = .finished
            return
        }
        initRetried = true
        startByte = P.otherFamily(startByte)
        log("keine Init-Quittung – versuche Startbyte \(hexByte(startByte))")
        proceed(to: .initialize)
    }

    private func armStepTimeout() {
        let s = step
        armTimeout(10) { [weak self] in
            self?.log("keine Antwort der Waage (Schritt \(s))")
            self?.status(String(localized: "Waage antwortet nicht"))
        }
    }

    private func armTimeout(_ seconds: TimeInterval, _ action: @escaping () -> Void) {
        timeoutToken += 1
        let token = timeoutToken
        scheduleTimeout(seconds) { [weak self] in
            guard let self, self.timeoutToken == token, self.link != nil else { return }
            action()
        }
    }

    private func cancelTimeout() {
        timeoutToken += 1
    }

    // MARK: Rückkanal

    private func hexByte(_ b: UInt8) -> String {
        String(format: "0x%02X", Int(b))
    }

    private func send(_ bytes: [UInt8]) {
        link?.send(Data(bytes))
    }

    private func log(_ line: String) {
        link?.log("[Beurer] \(line)")
    }

    private func status(_ text: String) {
        link?.status(text)
    }
}
