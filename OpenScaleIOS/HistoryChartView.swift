// SPDX-License-Identifier: GPL-3.0-or-later
//
// OpenTara – lokale Körperwaagen-App

import SwiftUI
import Charts

/// Verlaufs-Diagramm mit Glättungskurve (EWMA) und Trend-Rate.
/// Alle Werte werden pro Messung aus Gewicht + Impedanz + Profil neu berechnet.
struct HistoryChartView: View {
    let profile: UserProfile
    let measurements: [ScaleMeasurement]   // beliebige Reihenfolge
    var unit: WeightUnit = .kg

    enum Metric: String, CaseIterable, Identifiable {
        case weight, bmi, fat, water, muscle, bone, visceral, protein, bmr, metaage, lbm
        var id: String { rawValue }
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

    enum Period: String, CaseIterable, Identifiable {
        case d30, d90, y1, all
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .d30: return 30
            case .d90: return 90
            case .y1:  return 365
            case .all: return nil
            }
        }
        var title: LocalizedStringKey {
            switch self {
            case .d30: return "30 Tage"
            case .d90: return "90 Tage"
            case .y1:  return "1 Jahr"
            case .all: return "Alles"
            }
        }
    }

    @State private var metric: Metric = .weight
    @State private var period: Period = .d30

    private struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private func rawValue(_ m: ScaleMeasurement) -> Double? {
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
        let cutoff = period.days.flatMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: Date())
        }
        return measurements
            .filter { cutoff == nil || $0.date >= cutoff! }
            .compactMap { m in rawValue(m).map { ChartPoint(date: m.date, value: $0) } }
            .sorted { $0.date < $1.date }
    }

    /// Exponentiell geglättete Trendkurve.
    private var trendPoints: [ChartPoint] {
        let pts = points
        guard let first = pts.first else { return [] }
        let alpha = 0.3
        var t = first.value
        return pts.map { p in
            t += alpha * (p.value - t)
            return ChartPoint(date: p.date, value: t)
        }
    }

    /// Änderung pro Woche (lineare Regression über den Zeitraum).
    private var weeklyRate: Double? {
        let pts = points
        guard pts.count >= 2, let first = pts.first,
              let last = pts.last, last.date > first.date else { return nil }
        let x = pts.map { $0.date.timeIntervalSince(first.date) / 86_400.0 }
        let y = pts.map { $0.value }
        let n = Double(x.count)
        let sx = x.reduce(0, +), sy = y.reduce(0, +)
        let sxy = zip(x, y).map { $0 * $1 }.reduce(0, +)
        let sx2 = x.map { $0 * $0 }.reduce(0, +)
        let denom = n * sx2 - sx * sx
        guard abs(denom) > 1e-9 else { return nil }
        return (n * sxy - sx * sy) / denom * 7.0
    }

    private var suffix: String {
        switch metric {
        case .fat, .water, .protein: return "%"
        case .bmr: return "kcal"
        case .weight, .muscle, .bone, .lbm: return unit.short
        default: return ""
        }
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

            Picker("", selection: $period) {
                ForEach(Period.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            let pts = points
            if pts.count < 2 {
                Text(metric.needsImpedance
                     ? "Mindestens zwei Barfuß-Messungen (mit Impedanz) nötig."
                     : "Mindestens zwei Messungen nötig für ein Diagramm.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                let measLabel = String(localized: "Messungen")
                let trendLabel = String(localized: "Trend (geglättet)")
                Chart {
                    ForEach(pts) { pt in
                        PointMark(x: .value("Datum", pt.date),
                                  y: .value("Wert", pt.value))
                            .foregroundStyle(by: .value("Serie", measLabel))
                            .symbolSize(24)
                    }
                    ForEach(trendPoints) { pt in
                        LineMark(x: .value("Datum", pt.date),
                                 y: .value("Wert", pt.value))
                            .foregroundStyle(by: .value("Serie", trendLabel))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                    }
                }
                .chartForegroundStyleScale([
                    measLabel: Color.secondary.opacity(0.5),
                    trendLabel: Color.accentColor,
                ])
                .chartLegend(position: .bottom)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 210)

                if let r = weeklyRate {
                    let arrow = r > 0.005 ? "arrow.up.right"
                        : (r < -0.005 ? "arrow.down.right" : "arrow.right")
                    let rateStr = String(format: "%+.2f %@", r, suffix)
                    Label(String(localized: "Trend: \(rateStr)/Woche"), systemImage: arrow)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
