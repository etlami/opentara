// SPDX-License-Identifier: GPL-3.0-or-later
//
// OpenTara – lokale Körperwaagen-App
//
// Bewertungstabellen, Körpertyp und Body Score aus bodymiscale portiert
// (dckiller51/bodymiscale, GPLv3). Protein/Körpertyp/Score in Xiaomi-Logik,
// damit sie zur offiziellen Mi-Fit/Zepp-Life-Anzeige passen.

import Foundation

/// Bewertungstabellen für Körperfett und Muskelmasse.
struct RatingScale {
    let heightCm: Double
    let sex: Sex

    /// [sehr niedrig, niedrig, normal, hoch] Körperfett-% nach Alter/Geschlecht.
    func fatPercentage(age: Int) -> [Double] {
        let table: [(Int, Int, [Double], [Double])] = [
            (0, 12, [12, 21, 30, 34], [7, 16, 25, 30]),
            (12, 14, [15, 24, 33, 37], [7, 16, 25, 30]),
            (14, 16, [18, 27, 36, 40], [7, 16, 25, 30]),
            (16, 18, [20, 28, 37, 41], [7, 16, 25, 30]),
            (18, 40, [21, 28, 35, 40], [11, 17, 22, 27]),
            (40, 60, [22, 29, 36, 41], [12, 18, 23, 28]),
            (60, 101, [23, 30, 37, 42], [14, 20, 25, 30]),
        ]
        for row in table where age >= row.0 && age < row.1 {
            return sex == .female ? row.2 : row.3
        }
        let last = table[table.count - 1]
        return sex == .female ? last.2 : last.3
    }

    /// [niedrig, normal] Muskelmasse nach Größe/Geschlecht.
    var muscleMass: [Double] {
        let table: [(Double, Double, [Double], [Double])] = [
            (170, 160, [36.5, 42.6], [49.4, 59.5]),
            (160, 150, [32.9, 37.6], [44.0, 52.5]),
            (0, 0, [29.1, 34.8], [38.5, 46.6]),
        ]
        for row in table {
            let minH = sex == .male ? row.0 : row.1
            if heightCm >= minH { return sex == .female ? row.2 : row.3 }
        }
        let last = table[table.count - 1]
        return sex == .female ? last.2 : last.3
    }
}

/// Deutsche Bezeichnung für die neun Körpertyp-Schlüssel.
func bodyTypeLabel(_ key: String) -> String {
    switch key {
    case "obese":             return "Adipös"
    case "overweight":        return "Übergewichtig"
    case "thick_set":         return "Kräftig"
    case "lack_exercise":     return "Untrainiert"
    case "balanced":          return "Ausgewogen"
    case "balanced_muscular": return "Ausgewogen-muskulös"
    case "skinny":            return "Schlank"
    case "balanced_skinny":   return "Schlank-ausgewogen"
    case "skinny_muscular":   return "Schlank-muskulös"
    default:                  return key
    }
}

extension BodyMetrics {

    // MARK: - Protein & ideales Gewicht

    /// Protein-% (Xiaomi): (Muskel/Gewicht)×100 − Wasser%.
    func proteinPercentage() -> Double {
        let p = (muscleMass() / weight) * 100 - waterPercentage()
        return min(max(p, 5), 32)
    }

    /// Ideales Gewicht nach Devine-Formel (kg).
    func idealWeightKg() -> Double {
        let inches = height / 2.54
        let over60 = max(0, inches - 60)
        let base = sex == .male ? 50.0 : 45.5
        return base + 2.3 * over60
    }

    // MARK: - Körpertyp

    func bodyType() -> String {
        let scale = RatingScale(heightCm: height, sex: sex)
        let fat = fatPercentage()
        let muscle = muscleMass()
        let f = scale.fatPercentage(age: Int(age))
        let factor = fat > f[2] ? 0 : (fat < f[1] ? 2 : 1)
        let m = scale.muscleMass
        let mFactor = muscle > m[1] ? 2 : (muscle < m[0] ? 0 : 1)
        let idx = mFactor + factor * 3
        let keys = ["obese", "overweight", "thick_set", "lack_exercise",
                    "balanced", "balanced_muscular", "skinny",
                    "balanced_skinny", "skinny_muscular"]
        return keys[min(max(idx, 0), keys.count - 1)]
    }

    // MARK: - Body Score (10..100)

    private func malus(_ data: Double, _ minData: Double, _ maxData: Double,
                       _ maxMalus: Double, _ minMalus: Double) -> Double {
        if minData - maxData == 0 { return 0 }
        let r = ((data - maxData) / (minData - maxData)) * (maxMalus - minMalus)
        return max(0, r)
    }

    private func commonDeduct(_ minV: Double, _ maxV: Double, _ v: Double) -> Double {
        if v >= maxV { return 0 }
        if v < minV { return 10 }
        return malus(v, minV, maxV, 10, 5) + 5
    }

    func bodyScore() -> Double {
        let scale = RatingScale(heightCm: height, sex: sex)
        let fScale = scale.fatPercentage(age: Int(age))
        let fat = fatPercentage()
        let bmiVal = bmi()

        // BMI
        var bmiD = 0.0
        if height >= 90 {
            if bmiVal <= 14 {
                bmiD = 30
            } else if fat < fScale[2] && ((bmiVal >= 18.5 && age >= 18) || (bmiVal >= 15 && age < 18)) {
                bmiD = 0
            } else if bmiVal < 15 {
                bmiD = malus(bmiVal, 14, 15, 30, 15) + 15
            } else if bmiVal < 18.5 && age >= 18 {
                bmiD = malus(bmiVal, 15, 18.5, 15, 5) + 5
            } else if fat >= fScale[2] {
                if bmiVal >= 32 { bmiD = 10 }
                else if bmiVal > 28 { bmiD = malus(bmiVal, 28, 25, 5, 10) + 5 }
            }
        }

        // Körperfett
        let bestFat = sex == .male ? fScale[2] - 3 : fScale[2] - 2
        var fatD = 0.0
        if fat >= fScale[0] && fat < bestFat {
            fatD = 0
        } else if fat >= fScale[3] {
            fatD = 20
        } else {
            fatD = malus(fat, fScale[3], fScale[2], 20, 10) + 10
        }

        // Muskelmasse
        let mScale = scale.muscleMass
        let muscle = muscleMass()
        let muscleD = muscle > 0 ? commonDeduct(mScale[0] - 5, mScale[0], muscle) : 0

        // Wasser
        let waterNormal = sex == .male ? 55.0 : 45.0
        let waterD = commonDeduct(waterNormal - 5, waterNormal, waterPercentage())

        // Viszeralfett
        let vf = visceralFat()
        var viscD = 0.0
        if vf < 10 { viscD = 0 } else if vf >= 15 { viscD = 15 } else { viscD = malus(vf, 15, 10, 15, 10) + 10 }

        // Knochenmasse
        let boneEntries: [(Double, Double)] = sex == .male
            ? [(75, 2.0), (60, 1.9), (0, 1.6)]
            : [(60, 1.8), (45, 1.5), (0, 1.3)]
        var expectedBone = boneEntries[boneEntries.count - 1].1
        for e in boneEntries where weight >= e.0 { expectedBone = e.1; break }
        let boneD = commonDeduct(expectedBone - 0.3, expectedBone, boneMass())

        // Grundumsatz
        let bmrCoeffs: [(Int, Double)] = sex == .male
            ? [(30, 21.6), (50, 20.07), (100, 19.35)]
            : [(30, 21.24), (50, 19.53), (100, 18.63)]
        var normalBmr = 20.0
        for c in bmrCoeffs where age < Double(c.0) { normalBmr = weight * c.1; break }
        let bmrVal = bmr()
        var bmrD = 0.0
        if bmrVal >= normalBmr { bmrD = 0 } else if bmrVal <= normalBmr - 300 { bmrD = 6 } else { bmrD = malus(bmrVal, normalBmr - 300, normalBmr, 6, 3) + 5 }

        // Protein
        let p = proteinPercentage()
        var protD = 0.0
        if p > 17 { protD = 0 } else if p < 10 { protD = 10 } else if p <= 16 { protD = malus(p, 10, 16, 10, 5) + 5 } else { protD = malus(p, 16, 17, 5, 3) + 3 }

        let score = 100 - (bmiD + fatD + muscleD + waterD + viscD + boneD + bmrD + protD)
        return min(max(score, 10), 100)
    }
}
