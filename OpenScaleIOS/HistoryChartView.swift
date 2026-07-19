// SPDX-License-Identifier: GPL-3.0-or-later
//
// Freescale – lokale Körperwaagen-App

import SwiftUI
import Charts

/// Verlaufs-Diagramm über die gespeicherten Messungen des aktiven Profils.
struct HistoryChartView: View {
    let profile: UserProfile
    let measurements: [ScaleMeasurement]   // beliebige Reihenfolge
    var unit: WeightUnit = .kg

    enum Metric: String, CaseIterable, Identifiable {
        case weight = "Gewicht"
        case bmi    = "BMI"
        case fat    = "Körperfett"
        var id: String { rawValue }
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
        case .fat:
            guard let imp = m.impedance else { return nil }
            return BodyMetrics(weight: m.weightKg, height: profile.heightCm,
                               age: profile.ageYears, sex: profile.sex, impedance: imp).fatPercentage()
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
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            let pts = points
            if pts.count < 2 {
                Text("Mindestens zwei Messungen nötig für ein Diagramm.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart(pts) { pt in
                    LineMark(x: .value("Datum", pt.date),
                             y: .value(metric.rawValue, pt.value))
                    .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Datum", pt.date),
                              y: .value(metric.rawValue, pt.value))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 200)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
