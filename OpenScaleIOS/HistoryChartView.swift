// SPDX-License-Identifier: GPL-3.0-or-later
//
// OpenTara – lokale Körperwaagen-App

import SwiftUI
import Charts

/// Verlaufs-Diagramm über die gespeicherten Messungen des aktiven Profils.
/// Alle Werte werden pro Messung aus Gewicht + Impedanz + Profil neu berechnet.
struct HistoryChartView: View {
    let profile: UserProfile
    let measurements: [ScaleMeasurement]   // beliebige Reihenfolge
    var unit: WeightUnit = .kg

    enum Metric: String, CaseIterable, Identifiable {
        case weight, bmi, fat, water, muscle, bone, visceral, protein, bmr, metaage, lbm
        var id: String { rawValue }

        /// Braucht dieser Wert Impedanz (barfuß)?
        var needsImpedance: Bool { self != .weight && self != .bmi }

        var title: LocalizedStringKey {
            switch self {
            case .weight:   return "Gewicht"
            case .bmi:      return "BMI"
            case .fat:      return "Körperfett"
            case .water:    return "Wasser"
            case .muscle:   return "Muskelmasse"
            case .bone:     return "Knochenmasse"
            case .visceral: return "Viszeralfett"
            case .protein:  return "Protein"
            case .bmr:      return "Grundumsatz"
            case .metaage:  return "Metabol. Alter"
            case .lbm:      return "Fettfreie Masse"
            }
        }
    }

    @State private var metric: Metric = .weight

    private struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private func value(for m: ScaleMeasurement) -> Double? {
        switch metric {
        case .weight:
            return unit.fromKg(m.weightKg)
        case .bmi:
            return m.weightKg / pow(profile.heightCm / 100, 2)
        default:
            guard let imp = m.impedance else { return nil }
            let c = BodyMetrics(weight: m.weightKg, height: profile.heightCm,
                                age: profile.ageYears, sex: profile.sex, impedance: imp).compute()
            switch metric {
            case .fat:      return c.fatPercent
            case .water:    return c.waterPercent
            case .muscle:   return unit.fromKg(c.muscleMassKg)
            case .bone:     return unit.fromKg(c.boneMassKg)
            case .visceral: return c.visceralFat
            case .protein:  return c.proteinPercent
            case .bmr:      return c.bmr
            case .metaage:  return c.metabolicAge
            case .lbm:      return unit.fromKg(c.lbmKg)
            default:        return nil
            }
        }
    }

    private var points: [ChartPoint] {
        measurements
            .compactMap { m in value(for: m).map { ChartPoint(date: m.date, value: $0) } }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Diagramm").font(.headline)
                Spacer()
                Picker("", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }

            let pts = points
            if pts.count < 2 {
                Text(metric.needsImpedance
                     ? "Mindestens zwei Barfuß-Messungen (mit Impedanz) nötig."
                     : "Mindestens zwei Messungen nötig für ein Diagramm.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart(pts) { pt in
                    LineMark(x: .value("Datum", pt.date),
                             y: .value("Wert", pt.value))
                    .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Datum", pt.date),
                              y: .value("Wert", pt.value))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 200)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
