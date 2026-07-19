// SPDX-License-Identifier: GPL-3.0-or-later
//
// OpenTara – lokale Körperwaagen-App

import SwiftUI

struct GoalCardView: View {
    let profile: UserProfile
    let history: [ScaleMeasurement]
    let unit: WeightUnit

    var body: some View {
        if let target = profile.targetWeightKg,
           let status = GoalCalculator.status(history: history, target: target,
                                              goalSetDate: profile.goalSetDate) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ziel").font(.headline)

                HStack(spacing: 16) {
                    ring(status.fraction)
                    VStack(alignment: .leading, spacing: 6) {
                        row("Aktuell", unit.format(kg: status.current))
                        row("Ziel", unit.format(kg: status.target))
                        row(status.remainingKg >= 0 ? "Noch abnehmen" : "Noch zunehmen",
                            unit.format(kg: abs(status.remainingKg)))
                        if let d = status.projectedDate {
                            row("Prognose", d.formatted(.dateTime.day().month().year()))
                        }
                    }
                    Spacer()
                }

                if let rate = status.ratePerDay {
                    Text(rateText(rate))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Für eine Prognose sind mehrere Messungen über mindestens einen Tag nötig.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func ring(_ fraction: Double) -> some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((fraction * 100).rounded())) %").font(.headline)
        }
        .frame(width: 96, height: 96)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.semibold).monospacedDigit()
        }
    }

    private func rateText(_ ratePerDay: Double) -> String {
        let perWeek = ratePerDay * 7
        let dir = perWeek < -0.01 ? "abnehmend" : (perWeek > 0.01 ? "zunehmend" : "stabil")
        return String(format: "Tempo: %.2f %@/Woche (%@)",
                      unit.fromKg(abs(perWeek)), unit.short, dir)
    }
}
