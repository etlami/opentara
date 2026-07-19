// SPDX-License-Identifier: GPL-3.0-or-later
//
// Freescale – lokale Körperwaagen-App

import SwiftUI

/// Grobe Einordnung eines Werts – nur zur Orientierung, keine medizinische Bewertung.
enum AssessmentLevel {
    case low, normal, elevated, high, unknown

    var color: Color {
        switch self {
        case .low:      return .blue
        case .normal:   return .green
        case .elevated: return .orange
        case .high:     return .red
        case .unknown:  return .primary
        }
    }
}

/// Vereinfachte Referenzbereiche (alters-vereinfacht). Bewusst konservativ.
enum Assessment {

    static func bmi(_ v: Double) -> AssessmentLevel {
        switch v {
        case ..<18.5: return .low
        case ..<25:   return .normal
        case ..<30:   return .elevated
        default:      return .high
        }
    }

    /// WHO-Gewichtsklasse zum BMI.
    static func bmiCategory(_ v: Double) -> String {
        switch v {
        case ..<18.5: return "Untergewicht"
        case ..<25:   return "Normalgewicht"
        case ..<30:   return "Übergewicht"
        case ..<35:   return "Adipositas Grad I"
        case ..<40:   return "Adipositas Grad II"
        default:      return "Adipositas Grad III"
        }
    }

    static func bodyFat(_ v: Double, sex: Sex) -> AssessmentLevel {
        if sex == .male {
            switch v {
            case ..<8:  return .low
            case ..<20: return .normal
            case ..<25: return .elevated
            default:    return .high
            }
        } else {
            switch v {
            case ..<21: return .low
            case ..<33: return .normal
            case ..<39: return .elevated
            default:    return .high
            }
        }
    }

    static func water(_ v: Double, sex: Sex) -> AssessmentLevel {
        let lower = sex == .male ? 50.0 : 45.0
        return v < lower ? .elevated : .normal
    }

    static func visceralFat(_ v: Double) -> AssessmentLevel {
        switch v {
        case ..<10: return .normal
        case ..<15: return .elevated
        default:    return .high
        }
    }
}
