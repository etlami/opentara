// SPDX-License-Identifier: GPL-3.0-or-later
//
// OpenTara – lokale Körperwaagen-App
// Tests für den Beurer/Sanitas-Treiber. Byte-Beispiele nach dem openScale-Wiki
// (https://github.com/oliexdev/openScale/wiki/Beurer-Sanitas); keine Hardware nötig.

import Testing
import Foundation
import CoreBluetooth
@testable import OpenScaleIOS

private typealias P = BeurerSanitasProtocol

/// Fängt ab, was der Treiber an die Waage schickt, loggt oder als Status meldet,
/// und sammelt die Timeouts, statt sie zu planen.
private final class LinkRecorder {
    var sent: [[UInt8]] = []
    var logs: [String] = []
    var statuses: [String] = []
    var timeouts: [(seconds: TimeInterval, fire: () -> Void)] = []

    func link(user: ScaleUserContext?) -> ScaleDriverLink {
        ScaleDriverLink(
            user: user,
            send: { data in self.sent.append([UInt8](data)) },
            log: { line in self.logs.append(line) },
            status: { text in self.statuses.append(text) }
        )
    }
}

private let uid101: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0x65]
private let zeroUid = [UInt8](repeating: 0, count: 8)

/// 22-Byte-Messung: Zeitstempel 0xEA9290C2 (Bit 31 gesetzt → 0x6A9290C2 = 1787990210),
/// 83,00 kg, 500 Ω, 20,0 % Fett, 55,0 % Wasser, 42,0 % Muskel, 3,00 kg Knochen,
/// BMR 1800, AMR 2500, BMI 25,0.
private let measurementBytes: [UInt8] = [
    0xEA, 0x92, 0x90, 0xC2, 0x06, 0x7C, 0x01, 0xF4, 0x00, 0xC8, 0x02,
    0x26, 0x01, 0xA4, 0x00, 0x3C, 0x07, 0x08, 0x09, 0xC4, 0x00, 0xFA,
]
private let measurementTimestamp: TimeInterval = 1_787_990_210

private func berlinCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return cal
}

private func fabian(unit: WeightUnit = .kg) -> ScaleUserContext {
    let birth = berlinCalendar().date(from: DateComponents(year: 1985, month: 3, day: 7))!
    return ScaleUserContext(name: "Fabian", birthDate: birth, heightCm: 180, sex: .male,
                            activityLevel: 3, weightUnit: unit)
}

/// Treiber bis nach `onReady` hochfahren; Zeit steht 21 s nach dem Mess-Zeitstempel.
private func readyDriver(name: String, user: ScaleUserContext?) -> (BeurerSanitasDriver, LinkRecorder, ScaleDriverLink) {
    let driver = BeurerSanitasDriver()
    let rec = LinkRecorder()
    driver.calendar = berlinCalendar()
    driver.now = { Date(timeIntervalSince1970: measurementTimestamp + 21) }
    driver.scheduleTimeout = { seconds, fire in rec.timeouts.append((seconds, fire)) }
    #expect(driver.matches(name: name, serviceData: [:], advertised: []))
    let link = rec.link(user: user)
    driver.onReady(link)
    return (driver, rec, link)
}

private func feed(_ driver: BeurerSanitasDriver, _ link: ScaleDriverLink, _ frame: [UInt8]) -> ScaleReading? {
    driver.handle(characteristic: P.characteristicUUID, data: Data(frame), link: link)
}

// MARK: - Modellerkennung

struct BeurerSanitasModelTests {

    @Test func detectsModelsByNameLikeOpenScale() {
        #expect(P.model(forName: "BF-700") == .beurerBF700_800_RTLibra)
        #expect(P.model(forName: "Beurer BF700") == .beurerBF700_800_RTLibra)
        #expect(P.model(forName: "BEURER BF800") == .beurerBF700_800_RTLibra)
        #expect(P.model(forName: "RT-Libra-B") == .beurerBF700_800_RTLibra)
        #expect(P.model(forName: "BF700") == .beurerBF710)          // openScale: nackter Name = BF710
        #expect(P.model(forName: "Beurer BF710") == .beurerBF710)
        #expect(P.model(forName: "SANITAS SBF70") == .sanitasSBF70_75)
        #expect(P.model(forName: "sbf75") == .sanitasSBF70_75)
        #expect(P.model(forName: "AICDSCALE1") == .sanitasSBF70_75)
        #expect(P.model(forName: "MIBFS") == nil)
        #expect(P.model(forName: "") == nil)
        #expect(P.model(forName: nil) == nil)
    }

    @Test func startBytesPerModel() {
        #expect(P.Model.beurerBF700_800_RTLibra.startByte == 0xF7)
        #expect(P.Model.beurerBF710.startByte == 0xE7)
        #expect(P.Model.sanitasSBF70_75.startByte == 0xE7)
    }

    @Test func driverMatchesOnlyKnownNames() {
        let d = BeurerSanitasDriver()
        #expect(d.matches(name: "Beurer BF800", serviceData: [:], advertised: []))
        #expect(d.model == .beurerBF700_800_RTLibra)
        #expect(!d.matches(name: "MI SCALE", serviceData: [:], advertised: []))
        #expect(d.kind == .connection)
        #expect(d.isTested == false)
        #expect(d.connectionProfile?.writeUUID == CBUUID(string: "FFE1"))
        #expect(d.connectionProfile?.notifyUUIDs == [CBUUID(string: "FFE1")])
        #expect(d.connectionProfile?.serviceUUIDs == [CBUUID(string: "FFE0")])
    }
}

// MARK: - Kommandos

struct BeurerSanitasCommandTests {

    @Test func alternativeStartBytes() {
        #expect(P.altStartByte(0xE7, nibble: P.nibbleInit) == 0xE6)
        #expect(P.altStartByte(0xF7, nibble: P.nibbleSetTime) == 0xF9)
        #expect(P.altStartByte(0xE7, nibble: P.nibbleDisconnect) == 0xEA)
        #expect(P.otherFamily(0xE7) == 0xF7)
        #expect(P.otherFamily(0xF7) == 0xE7)
    }

    @Test func initSetTimeAndDisconnect() {
        #expect(P.initCommand(startByte: 0xF7) == [0xF6, 0x01])
        #expect(P.initCommand(startByte: 0xE7) == [0xE6, 0x01])
        let date = Date(timeIntervalSince1970: 0x6A92_90AD)
        #expect(P.setTimeCommand(startByte: 0xE7, date: date) == [0xE9, 0x6A, 0x92, 0x90, 0xAD])
        #expect(P.disconnectCommand(startByte: 0xF7) == [0xFA, 0x02])
    }

    @Test func statusAndUserListCommands() {
        #expect(P.command(startByte: 0xE7, P.Cmd.scaleStatus, payload: P.encodeUserId(0)) == [0xE7, 0x4F] + zeroUid)
        #expect(P.command(startByte: 0xF7, P.Cmd.userList) == [0xF7, 0x33])
        #expect(P.command(startByte: 0xE7, P.Cmd.doMeasurement, payload: P.encodeUserId(101)) == [0xE7, 0x40] + uid101)
        #expect(P.command(startByte: 0xE7, P.Cmd.setUnit, payload: [P.unitCode(for: .lb)]) == [0xE7, 0x4D, 0x02])
        #expect(P.unitCode(for: .kg) == 1)
        #expect(P.unitCode(for: .st) == 4)
    }

    @Test func appAckEchoesCommandCountAndCurrent() {
        #expect(P.ack(startByte: 0xE7, for: [0xE7, 0x58, 0x01, 0x06, 0x7C]) == [0xE7, 0xF1, 0x58, 0x01, 0x06])
        #expect(P.ack(startByte: 0xE7, for: [0xE7, 0x59, 0x03, 0x02, 0xAA, 0xBB]) == [0xE7, 0xF1, 0x59, 0x03, 0x02])
        #expect(P.ack(startByte: 0xF7, for: [0xF7, 0x34, 0x02, 0x01] + uid101) == [0xF7, 0xF1, 0x34, 0x02, 0x01])
    }

    @Test func userIdRoundTrip() {
        #expect(P.encodeUserId(101) == uid101)
        #expect(P.encodeUserId(0x0102_0304_0506_0708) == [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(P.decodeUserId([0xE7, 0x34, 0x02, 0x01] + uid101, at: 4) == 101)
        #expect(P.decodeUserId([1, 2, 3, 4, 5, 6, 7, 8], at: 0) == 0x0102_0304_0506_0708)
        #expect(P.decodeUserId([1, 2, 3], at: 0) == nil)
    }

    @Test func scaleNameIsAsciiUppercase() {
        #expect(P.scaleName(for: "Fabian") == "FABIAN")
        #expect(P.scaleName(for: "Jörg Müller") == "JORGMULLER")
        #expect(P.scaleName(for: "Élodie") == "ELODIE")
        #expect(P.scaleName(for: "日本") == "OT")
        #expect(P.scaleName(for: "") == "OT")
        #expect(P.nameBytes("FABIAN") == [0x46, 0x41, 0x42])
        #expect(P.nameBytes("AL") == [0x41, 0x4C, 0x00])
        #expect(P.decodeName([0x41, 0x4C, 0x00, 0x55], at: 0) == "AL")
    }

    @Test func addUserCommandLayout() {
        let record = P.userRecord(from: fabian(), uid: 101, calendar: berlinCalendar())
        #expect(record == P.UserRecord(uid: 101, name: "FABIAN", birthYear: 1985, birthMonth: 3, birthDay: 7,
                                       heightCm: 180, isMale: true, activityLevel: 3))
        // <sb> 31 <uid 8> <name 3> <year-1900> <month 0-basiert> <day> <height> <sex|activity>
        let expected: [UInt8] = [0xE7, 0x31] + uid101 + [0x46, 0x41, 0x42, 0x55, 0x02, 0x07, 0xB4, 0x83]
        #expect(P.addUserCommand(startByte: 0xE7, user: record) == expected)

        var female = record
        female.isMale = false
        female.activityLevel = 5
        #expect(P.addUserCommand(startByte: 0xE7, user: female).last == 0x05)
    }
}

// MARK: - Frames

struct BeurerSanitasFrameTests {

    @Test func parsesScaleStatus() {
        let s = P.parseStatus([0xE7, 0xF0, 0x4F, 0x00, 0x5A, 0x28, 0xDC, 0x01, 0x00, 0x01, 0x00, 0x03])
        #expect(s == P.Status(batteryPercent: 90, weightThresholdKg: 4.0, fatThresholdPercent: 22.0, unitCode: 1,
                              userExists: true, userReferenceWeightExists: false, userMeasurementExists: true,
                              version: 3))
        #expect(P.parseStatus([0xE7, 0xF0, 0x4F, 0x00]) == nil)
    }

    @Test func parsesUserListEntry() {
        let e = P.parseUserListEntry([0xE7, 0x34, 0x02, 0x01] + uid101 + [0x46, 0x41, 0x42, 0x55])
        #expect(e == P.UserListEntry(count: 2, current: 1, uid: 101, name: "FAB", birthYear: 1985))
        #expect(P.parseUserListEntry([0xE7, 0x34, 0x02, 0x01]) == nil)
    }

    @Test func parsesUserDetails() {
        let d = P.parseUserDetails([0xE7, 0xF0, 0x36, 0x00, 0x46, 0x41, 0x42, 0x55, 0x02, 0x07, 0xB4, 0x83])
        #expect(d == P.UserRecord(uid: 0, name: "FAB", birthYear: 1985, birthMonth: 3, birthDay: 7,
                                  heightCm: 180, isMale: true, activityLevel: 3))
        #expect(P.parseUserDetails([0xE7, 0xF0, 0x36, 0x01, 0, 0, 0, 0, 0, 0, 0, 0]) == nil)
    }

    @Test func parsesLiveWeight() {
        #expect(P.parseLiveWeight([0xE7, 0x58, 0x01, 0x06, 0x7C]) == P.LiveWeight(isStable: false, weightKg: 83.0))
        #expect(P.parseLiveWeight([0xE7, 0x58, 0x00, 0x06, 0x7C]) == P.LiveWeight(isStable: true, weightKg: 83.0))
        #expect(P.parseLiveWeight([0xE7, 0x58, 0x00]) == nil)
    }

    /// Echte Frames eines Beurer BF700 (meldet sich als "BF700") vom 24.10.2026: 103,40 kg, 510 Ω.
    @Test func parsesRealBF700Frames() {
        let status = P.parseStatus([0xE7, 0xF0, 0x4F, 0x01, 0x4F, 0x14, 0xDC, 0x01, 0x01, 0x01, 0x01, 0x05])
        #expect(status?.batteryPercent == 79)
        #expect(status?.weightThresholdKg == 2.0)
        #expect(status?.fatThresholdPercent == 22.0)
        #expect(status?.unitCode == 1)
        #expect(status?.version == 5)

        let entry = P.parseUserListEntry([0xE7, 0x34, 0x01, 0x01, 0, 0, 0, 0, 0, 0, 0, 0x65, 0x46, 0x41, 0x42, 0x63])
        #expect(entry == P.UserListEntry(count: 1, current: 1, uid: 101, name: "FAB", birthYear: 1999))

        #expect(P.parseLiveWeight([0xE7, 0x58, 0x01, 0x00, 0xB1]) == P.LiveWeight(isStable: false, weightKg: 8.85))
        #expect(P.parseLiveWeight([0xE7, 0x58, 0x00, 0x08, 0x14]) == P.LiveWeight(isStable: true, weightKg: 103.4))

        let part2: [UInt8] = [0x6A, 0xDC, 0xFC, 0x2B, 0x08, 0x14, 0x01, 0xFE, 0x01, 0x4C, 0x01]
        let part3: [UInt8] = [0xB6, 0x01, 0x61, 0x01, 0x20, 0x08, 0x93, 0x0C, 0xDD, 0x01, 0x46]
        let m = P.parseMeasurement(part2 + part3)
        #expect(m?.timestamp == 0x6ADC_FC2B)          // = gesetzte Uhrzeit 0x6ADCFC17 + 20 s, kein Bit 31
        #expect(m?.weightKg == 103.4)
        #expect(m?.impedanceOhm == 510)
        #expect(m?.fatPercent == 33.2)
        #expect(m?.waterPercent == 43.8)
        #expect(m?.musclePercent == 35.3)
        #expect(m?.boneRaw == 288)
        #expect(m?.bmrKcal == 2195)
        #expect(m?.amrKcal == 3293)
        #expect(m?.bmi == 32.6)                        // passt zu 103,4 kg / 1,78 m
    }

    @Test func parsesMeasurementAndMasksBit31() {
        let m = P.parseMeasurement(measurementBytes)
        #expect(m == P.Measurement(timestamp: 0x6A92_90C2, weightKg: 83.0, impedanceOhm: 500,
                                   fatPercent: 20.0, waterPercent: 55.0, musclePercent: 42.0, boneKg: 3.0,
                                   boneRaw: 60, bmrKcal: 1800, amrKcal: 2500, bmi: 25.0))
        #expect(m?.date == Date(timeIntervalSince1970: measurementTimestamp))
        #expect(P.parseMeasurement(Array(measurementBytes.dropLast())) == nil)
    }
}

// MARK: - Zustandsmaschine

struct BeurerSanitasDriverFlowTests {

    @Test func fullFlowWithExistingUser() {
        let (driver, rec, link) = readyDriver(name: "BF700", user: fabian())
        #expect(driver.startByte == 0xE7)
        #expect(driver.step == .initialize)
        #expect(rec.sent == [[0xE6, 0x01]])

        // Init-Quittung → Uhrzeit + Statusabfrage
        #expect(feed(driver, link, [0xE6, 0x00, 0x20]) == nil)
        #expect(rec.sent[1] == [0xE9, 0x6A, 0x92, 0x90, 0xD7])
        #expect(rec.sent[2] == [0xE7, 0x4F] + zeroUid)

        // Status (kg, Batterie 90 %) → Nutzerliste
        #expect(feed(driver, link, [0xE7, 0xF0, 0x4F, 0x00, 0x5A, 0x28, 0xDC, 0x01, 0x00, 0x00, 0x00, 0x03]) == nil)
        #expect(rec.sent[3] == [0xE7, 0x33])
        #expect(feed(driver, link, [0xE7, 0xF0, 0x33, 0x00, 0x01, 0x08]) == nil)
        #expect(rec.sent.count == 4)

        // Eine Nutzerzeile: FAB 1985 → quittieren, wiedererkennen, Details abfragen
        #expect(feed(driver, link, [0xE7, 0x34, 0x01, 0x01] + uid101 + [0x46, 0x41, 0x42, 0x55]) == nil)
        #expect(rec.sent[4] == [0xE7, 0xF1, 0x34, 0x01, 0x01])
        #expect(driver.currentUser == BeurerSanitasDriver.RemoteUser(uid: 101, name: "FAB", birthYear: 1985))
        #expect(rec.sent[5] == [0xE7, 0x36] + uid101)

        // Details → Messung starten
        #expect(feed(driver, link, [0xE7, 0xF0, 0x36, 0x00, 0x46, 0x41, 0x42, 0x55, 0x02, 0x07, 0xB4, 0x83]) == nil)
        #expect(rec.sent[6] == [0xE7, 0x40] + uid101)
        #expect(feed(driver, link, [0xE7, 0xF0, 0x40, 0x00]) == nil)
        #expect(driver.step == .measuring)
        #expect(rec.statuses.last == String(localized: "Jetzt barfuß auf die Waage stellen"))

        // Live-Gewicht: instabil, dann stabil
        let live = feed(driver, link, [0xE7, 0x58, 0x01, 0x06, 0x7C])
        #expect(live?.weightKg == 83.0)
        #expect(live?.isStabilized == false)
        #expect(rec.sent[7] == [0xE7, 0xF1, 0x58, 0x01, 0x06])
        let stable = feed(driver, link, [0xE7, 0x58, 0x00, 0x06, 0x7C])
        #expect(stable?.weightKg == 83.0)
        #expect(stable?.isStabilized == true)
        #expect(stable?.impedance == nil)
        #expect(rec.sent[8] == [0xE7, 0xF1, 0x58, 0x00, 0x06])

        // Messung in drei Teilen
        #expect(feed(driver, link, [0xE7, 0x59, 0x03, 0x01, 0x01] + uid101) == nil)
        #expect(rec.sent[9] == [0xE7, 0xF1, 0x59, 0x03, 0x01])
        #expect(feed(driver, link, [0xE7, 0x59, 0x03, 0x02] + Array(measurementBytes[0..<11])) == nil)
        #expect(rec.sent[10] == [0xE7, 0xF1, 0x59, 0x03, 0x02])
        let full = feed(driver, link, [0xE7, 0x59, 0x03, 0x03] + Array(measurementBytes[11..<22]))
        #expect(rec.sent[11] == [0xE7, 0xF1, 0x59, 0x03, 0x03])
        #expect(full?.weightKg == 83.0)
        #expect(full?.impedance == 500)
        #expect(full?.isStabilized == true)
        #expect(full?.weightRemoved == false)
        #expect(full?.date == Date(timeIntervalSince1970: measurementTimestamp))
        #expect(full?.rawHex == P.hex(measurementBytes))
        #expect(full?.source == "Beurer BF710")
        #expect(driver.step == .finished)
        #expect(rec.sent.count == 12)
        #expect(rec.statuses.last == String(localized: "Messung abgeschlossen"))
    }

    @Test func createsUserWhenScaleHasNone() {
        let (driver, rec, link) = readyDriver(name: "Beurer BF800", user: fabian())
        #expect(driver.startByte == 0xF7)
        #expect(rec.sent == [[0xF6, 0x01]])
        _ = feed(driver, link, [0xF6, 0x00, 0x20])
        _ = feed(driver, link, [0xF7, 0xF0, 0x4F, 0x00, 0x5A, 0x28, 0xDC, 0x01, 0x01, 0x01, 0x01, 0x03])
        #expect(rec.sent[3] == [0xF7, 0x33])

        // Leere Nutzerliste → Nutzer anlegen mit uid 101
        _ = feed(driver, link, [0xF7, 0xF0, 0x33, 0x00, 0x00, 0x08])
        #expect(rec.sent[4] == [0xF7, 0x31] + uid101 + [0x46, 0x41, 0x42, 0x55, 0x02, 0x07, 0xB4, 0x83])
        #expect(driver.currentUser == BeurerSanitasDriver.RemoteUser(uid: 101, name: "FAB", birthYear: 1985))

        // Angelegt → direkt Messung starten (ohne Details-Abfrage); der neue Nutzer ist jetzt bekannt
        _ = feed(driver, link, [0xF7, 0xF0, 0x31, 0x00])
        #expect(rec.sent[5] == [0xF7, 0x40] + uid101)
        #expect(driver.step == .measure)
        #expect(driver.remoteUsers.map(\.uid) == [101])
    }

    @Test func reusesScaleUserWithSameNameButOtherBirthYear() {
        // Waage kennt FAB mit Geburtsjahr 1999 (so im Beurer-Log vom 24.10.2026), Profil sagt 1985.
        let (driver, rec, link) = readyDriver(name: "BF700", user: fabian())
        _ = feed(driver, link, [0xE6, 0x00, 0x20])
        _ = feed(driver, link, [0xE7, 0xF0, 0x4F, 0x01, 0x4F, 0x14, 0xDC, 0x01, 0x01, 0x01, 0x01, 0x05])
        _ = feed(driver, link, [0xE7, 0xF0, 0x33, 0x00, 0x01, 0x08])
        _ = feed(driver, link, [0xE7, 0x34, 0x01, 0x01] + uid101 + [0x46, 0x41, 0x42, 0x63])
        #expect(driver.currentUser == BeurerSanitasDriver.RemoteUser(uid: 101, name: "FAB", birthYear: 1999))
        #expect(rec.sent.last == [0xE7, 0x36] + uid101)          // Details, kein Anlegen
        #expect(!rec.sent.contains { $0.count > 1 && $0[1] == P.Cmd.userAdd })
        #expect(rec.logs.contains { $0.contains("Geburtsjahr 1999") })
    }

    @Test func nameAlreadyUsedFallsBackToExistingUser() {
        // Zwei FAB-Nutzer auf der Waage (uneindeutig) → Anlegen wird versucht, Waage sagt Code 3.
        let (driver, rec, link) = readyDriver(name: "BF700", user: fabian())
        _ = feed(driver, link, [0xE6, 0x00, 0x20])
        _ = feed(driver, link, [0xE7, 0xF0, 0x4F, 0x00, 0x5A, 0x28, 0xDC, 0x01, 0x00, 0x00, 0x00, 0x03])
        _ = feed(driver, link, [0xE7, 0xF0, 0x33, 0x00, 0x02, 0x08])
        _ = feed(driver, link, [0xE7, 0x34, 0x02, 0x01] + uid101 + [0x46, 0x41, 0x42, 0x63])
        _ = feed(driver, link, [0xE7, 0x34, 0x02, 0x02, 0, 0, 0, 0, 0, 0, 0, 0x66, 0x46, 0x41, 0x42, 0x65])
        #expect(rec.sent.last?[1] == P.Cmd.userAdd)
        _ = feed(driver, link, [0xE7, 0xF0, 0x31, 0x03])
        #expect(driver.currentUser?.uid == 101)
        #expect(rec.sent.last == [0xE7, 0x36] + uid101)
        #expect(driver.step == .userDetails)
    }

    @Test func newUidIsMaxPlusOne() {
        let (driver, rec, link) = readyDriver(name: "SANITAS SBF70", user: fabian())
        _ = feed(driver, link, [0xE6, 0x00, 0x20])
        _ = feed(driver, link, [0xE7, 0xF0, 0x4F, 0x00, 0x5A, 0x28, 0xDC, 0x01, 0x00, 0x00, 0x00, 0x03])
        _ = feed(driver, link, [0xE7, 0xF0, 0x33, 0x00, 0x02, 0x08])
        // Zwei fremde Nutzer: ANN 1970 (uid 5) und BOB 1985 (uid 200)
        _ = feed(driver, link, [0xE7, 0x34, 0x02, 0x01, 0, 0, 0, 0, 0, 0, 0, 5, 0x41, 0x4E, 0x4E, 0x46])
        _ = feed(driver, link, [0xE7, 0x34, 0x02, 0x02, 0, 0, 0, 0, 0, 0, 0, 200, 0x42, 0x4F, 0x42, 0x55])
        #expect(driver.remoteUsers.count == 2)
        #expect(rec.sent.last == [0xE7, 0x31] + [0, 0, 0, 0, 0, 0, 0, 201] + [0x46, 0x41, 0x42, 0x55, 0x02, 0x07, 0xB4, 0x83])
    }

    @Test func fullUserMemoryStopsGracefully() {
        let (driver, rec, link) = readyDriver(name: "BF700", user: fabian())
        _ = feed(driver, link, [0xE6, 0x00, 0x20])
        _ = feed(driver, link, [0xE7, 0xF0, 0x4F, 0x00, 0x5A, 0x28, 0xDC, 0x01, 0x00, 0x00, 0x00, 0x03])
        _ = feed(driver, link, [0xE7, 0xF0, 0x33, 0x00, 0x00, 0x08])
        let before = rec.sent.count
        _ = feed(driver, link, [0xE7, 0xF0, 0x31, 0x01])   // 01 = voll
        #expect(rec.sent.count == before)
        #expect(driver.step == .finished)
        #expect(driver.currentUser == nil)
        #expect(rec.statuses.last?.contains("voll") == true)
    }

    @Test func alignsScaleUnitWithProfile() {
        let (driver, rec, link) = readyDriver(name: "BF700", user: fabian(unit: .lb))
        _ = feed(driver, link, [0xE6, 0x00, 0x20])
        _ = feed(driver, link, [0xE7, 0xF0, 0x4F, 0x00, 0x5A, 0x28, 0xDC, 0x01, 0x00, 0x00, 0x00, 0x03])  // Waage: kg
        #expect(rec.sent.last == [0xE7, 0x4D, 0x02])
        #expect(driver.step == .setUnit)
        _ = feed(driver, link, [0xE7, 0xF0, 0x4D, 0x00])
        #expect(rec.sent.last == [0xE7, 0x33])
        #expect(driver.step == .userList)
    }

    @Test func initTimeoutSwitchesStartByteFamily() {
        let (driver, rec, link) = readyDriver(name: "BF700", user: fabian())
        #expect(rec.sent == [[0xE6, 0x01]])
        #expect(rec.timeouts.count == 1)
        #expect(rec.timeouts[0].seconds == 3)

        rec.timeouts[0].fire()
        #expect(driver.startByte == 0xF7)
        #expect(rec.sent.last == [0xF6, 0x01])

        // Die Waage antwortet in der anderen Familie → alle weiteren Kommandos mit 0xF7
        _ = feed(driver, link, [0xF6, 0x00, 0x20])
        #expect(rec.sent[2].first == 0xF9)
        #expect(rec.sent[3] == [0xF7, 0x4F] + zeroUid)

        // Ein abgelaufener Timeout darf nichts mehr auslösen
        let before = rec.sent.count
        rec.timeouts[0].fire()
        #expect(rec.sent.count == before)
    }

    @Test func secondInitTimeoutGivesUp() {
        let (driver, rec, _) = readyDriver(name: "BF700", user: fabian())
        rec.timeouts[0].fire()
        #expect(driver.step == .initialize)
        rec.timeouts.last!.fire()
        #expect(driver.step == .finished)
        #expect(rec.statuses.last == String(localized: "Waage antwortet nicht"))
    }

    @Test func ignoresFramesWithForeignStartByteAndOtherCharacteristics() {
        let (driver, rec, link) = readyDriver(name: "BF700", user: fabian())
        let before = rec.sent.count
        #expect(feed(driver, link, [0xF7, 0x58, 0x01, 0x06, 0x7C]) == nil)
        #expect(feed(driver, link, [0xE7]) == nil)
        #expect(driver.handle(characteristic: CBUUID(string: "2A9D"), data: Data([0xE7, 0x58, 0x00, 0x06, 0x7C]), link: link) == nil)
        #expect(rec.sent.count == before)
        #expect(driver.step == .initialize)
    }

    @Test func withoutProfileNoUserIsCreated() {
        let (driver, rec, link) = readyDriver(name: "BF700", user: nil)
        _ = feed(driver, link, [0xE6, 0x00, 0x20])
        _ = feed(driver, link, [0xE7, 0xF0, 0x4F, 0x00, 0x5A, 0x28, 0xDC, 0x01, 0x00, 0x00, 0x00, 0x03])
        let before = rec.sent.count
        _ = feed(driver, link, [0xE7, 0xF0, 0x33, 0x00, 0x00, 0x08])
        #expect(rec.sent.count == before)
        #expect(driver.step == .finished)
        #expect(driver.currentUser == nil)
    }

    @Test func implausibleTimestampFallsBackToNow() {
        let (driver, rec, link) = readyDriver(name: "BF700", user: fabian())
        driver.now = { Date(timeIntervalSince1970: measurementTimestamp + 10 * 86_400) }
        _ = feed(driver, link, [0xE7, 0x59, 0x03, 0x01, 0x01] + uid101)
        _ = feed(driver, link, [0xE7, 0x59, 0x03, 0x02] + Array(measurementBytes[0..<11]))
        let full = feed(driver, link, [0xE7, 0x59, 0x03, 0x03] + Array(measurementBytes[11..<22]))
        #expect(full?.date == nil)
        #expect(full?.weightKg == 83.0)
        #expect(rec.sent.count == 4)
    }

    @Test func disconnectResetsState() {
        let (driver, rec, link) = readyDriver(name: "BF700", user: fabian())
        _ = feed(driver, link, [0xE6, 0x00, 0x20])
        driver.onDisconnected()
        #expect(driver.step == .idle)
        let before = rec.sent.count
        rec.timeouts.last!.fire()
        #expect(rec.sent.count == before)
    }
}
