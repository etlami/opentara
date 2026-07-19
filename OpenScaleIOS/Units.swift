// SPDX-License-Identifier: GPL-3.0-or-later
//
// Freescale – lokale Körperwaagen-App

import Foundation

/// Gewichtseinheit für die Anzeige/Eingabe. Intern wird immer in kg gespeichert.
enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case kg, lb, st

    var id: String { rawValue }

    var short: String {
        switch self {
        case .kg: return "kg"
        case .lb: return "lb"
        case .st: return "st"
        }
    }

    var label: String {
        switch self {
        case .kg: return "Kilogramm (kg)"
        case .lb: return "Pfund (lb)"
        case .st: return "Stone (st)"
        }
    }

    private var perKg: Double {
        switch self {
        case .kg: return 1.0
        case .lb: return 2.2046226218
        case .st: return 0.1574730444
        }
    }

    /// kg -> Wert in dieser Einheit.
    func fromKg(_ kg: Double) -> Double { kg * perKg }

    /// Wert in dieser Einheit -> kg.
    func toKg(_ value: Double) -> Double { value / perKg }

    /// Formatiert einen kg-Wert in dieser Einheit inkl. Kürzel.
    func format(kg: Double, decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f %@", fromKg(kg), short)
    }
}

/// Optionale Körperwerte, die man in den Einstellungen aus-/einblenden kann.
enum MetricCatalog {
    static let optional: [(key: String, label: String)] = [
        ("fat", "Körperfett"),
        ("water", "Wasser"),
        ("muscle", "Muskelmasse"),
        ("bone", "Knochenmasse"),
        ("visceral", "Viszeralfett"),
        ("bmr", "Grundumsatz"),
        ("metaage", "Metabolisches Alter"),
        ("protein", "Protein"),
        ("lbm", "Fettfreie Masse (LBM)"),
        ("ideal", "Ideales Gewicht"),
        ("bodytype", "Körpertyp"),
        ("bodyscore", "Body Score"),
    ]
}
