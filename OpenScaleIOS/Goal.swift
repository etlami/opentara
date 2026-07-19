// SPDX-License-Identifier: GPL-3.0-or-later
//
// Freescale – lokale Körperwaagen-App

import Foundation

struct GoalStatus {
    let current: Double        // kg
    let target: Double         // kg
    let start: Double          // kg (älteste Messung)
    let fraction: Double       // 0...1 Fortschritt
    let remainingKg: Double    // vorzeichenbehaftet: current - target
    let ratePerDay: Double?    // kg/Tag (negativ = Abnahme)
    let projectedDate: Date?   // geschätztes Zieldatum
}

enum GoalCalculator {

    static func status(history: [ScaleMeasurement], target: Double, goalSetDate: Date?) -> GoalStatus? {
        guard let current = history.first?.weightKg else { return nil }

        // Startpunkt = Messung am nächsten zum Zielsetzungs-Datum, sonst älteste Messung.
        let start: Double
        if let setDate = goalSetDate,
           let nearest = history.min(by: {
               abs($0.date.timeIntervalSince(setDate)) < abs($1.date.timeIntervalSince(setDate))
           }) {
            start = nearest.weightKg
        } else if let oldest = history.last?.weightKg {
            start = oldest
        } else {
            return nil
        }

        // Fortschritt über den Abstand zum Ziel: 0 % = so weit weg wie am Start,
        // 100 % = am Ziel angekommen. Robust auch bei „krummen" Startwerten.
        let startDist = abs(start - target)
        let currentDist = abs(current - target)
        let fraction: Double
        if startDist < 0.0001 {
            fraction = currentDist < 0.05 ? 1 : 0
        } else {
            fraction = min(max(1 - currentDist / startDist, 0), 1)
        }

        let remaining = current - target
        let rate = slopePerDay(history)

        var projected: Date?
        if let rate, abs(rate) > 0.0001 {
            let delta = target - current          // benötigte (vorzeichenbehaftete) Änderung
            let days = delta / rate               // Tage bis zum Ziel
            if days > 0 && days < 3650 {
                projected = Calendar.current.date(byAdding: .day, value: Int(days.rounded()), to: Date())
            }
        }

        return GoalStatus(current: current, target: target, start: start,
                          fraction: fraction, remainingKg: remaining,
                          ratePerDay: rate, projectedDate: projected)
    }

    /// Steigung (kg/Tag) über eine lineare Regression aller Messpunkte.
    private static func slopePerDay(_ history: [ScaleMeasurement]) -> Double? {
        let pts = history.sorted { $0.date < $1.date }
        guard pts.count >= 2, let first = pts.first, let last = pts.last else { return nil }

        // Zu kurze Zeitspanne -> keine sinnvolle Rate/Prognose (verhindert Unsinn
        // wie „982 kg/Woche", wenn mehrere Messungen im Minutenabstand liegen).
        let spanDays = last.date.timeIntervalSince(first.date) / 86_400.0
        guard spanDays >= 1.0 else { return nil }

        let x = pts.map { $0.date.timeIntervalSince(first.date) / 86_400.0 }  // Tage
        let y = pts.map { $0.weightKg }
        let n = Double(x.count)
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).map { $0 * $1 }.reduce(0, +)
        let sumX2 = x.map { $0 * $0 }.reduce(0, +)

        let denom = n * sumX2 - sumX * sumX
        guard abs(denom) > 1e-9 else { return nil }
        return (n * sumXY - sumX * sumY) / denom
    }
}
