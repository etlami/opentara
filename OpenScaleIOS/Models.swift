// SPDX-License-Identifier: GPL-3.0-or-later
//
// Freescale – lokale Körperwaagen-App

import Foundation

// MARK: - Geschlecht

enum Sex: String, Codable, CaseIterable, Identifiable {
    case male
    case female

    var id: String { rawValue }

    var localized: String {
        switch self {
        case .male:   return "Männlich"
        case .female: return "Weiblich"
        }
    }
}

// MARK: - Benutzerprofil

struct UserProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var heightCm: Double
    var birthDate: Date
    var sex: Sex
    /// Zielgewicht in kg (optional).
    var targetWeightKg: Double? = nil
    /// Datum, an dem das Ziel gesetzt/geändert wurde – Startpunkt für den Fortschritt.
    var goalSetDate: Date? = nil

    /// Alter in vollen Jahren, bezogen auf heute.
    var ageYears: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
    }
}

// MARK: - Einzelmessung

struct ScaleMeasurement: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var weightKg: Double
    /// Impedanz in Ohm. `nil`, wenn nicht barfuß gemessen wurde.
    var impedance: Int?
    var isStabilized: Bool
    /// Roh-Bytes als Hex – nur zum Kalibrieren/Debuggen.
    var rawHex: String

    // Optionale, manuell erfassbare Zusatzmaße (openScale-kompatibel)
    var comment: String? = nil
    var waistCm: Double? = nil
    var hipCm: Double? = nil
    var chestCm: Double? = nil
    var thighCm: Double? = nil
    var bicepsCm: Double? = nil
    var neckCm: Double? = nil

    /// Verhältnis Taille/Größe (gesund < 0,5).
    func waistToHeight(height: Double) -> Double? {
        guard let waist = waistCm, height > 0 else { return nil }
        return waist / height
    }

    /// Verhältnis Taille/Hüfte.
    var waistToHip: Double? {
        guard let waist = waistCm, let hip = hipCm, hip > 0 else { return nil }
        return waist / hip
    }

    var hasCircumferences: Bool {
        waistCm != nil || hipCm != nil || chestCm != nil ||
        thighCm != nil || bicepsCm != nil || neckCm != nil
    }
}

// MARK: - Hilfen

func defaultBirthDate() -> Date {
    var c = DateComponents()
    c.year = 1990
    c.month = 1
    c.day = 1
    return Calendar.current.date(from: c) ?? Date()
}
