// SPDX-License-Identifier: GPL-3.0-or-later
//
// OpenTara – lokale Körperwaagen-App

import Foundation

/// Ergebnis einer Körperzusammensetzungs-Berechnung.
struct BodyComposition: Equatable {
    var bmi: Double
    var fatPercent: Double
    var waterPercent: Double
    var boneMassKg: Double
    var muscleMassKg: Double
    var visceralFat: Double
    var bmr: Double          // Grundumsatz in kcal
    var metabolicAge: Double
    var lbmKg: Double        // fettfreie Masse (Lean Body Mass)
    var proteinPercent: Double
    var idealWeightKg: Double
    var bodyTypeKey: String
    var bodyScore: Double
}

/// Portierung der Original-Xiaomi/Huami-Regressionsformeln (2017),
/// wie sie openScale, Zepp Life und Mi Fit verwenden.
/// Referenz: zibous/ha-miscale2 -> lib/body_metrics.py
struct BodyMetrics {
    let weight: Double      // kg
    let height: Double      // cm
    let age: Double         // Jahre
    let sex: Sex
    let impedance: Double   // Ohm

    init(weight: Double, height: Double, age: Int, sex: Sex, impedance: Int) {
        self.weight = weight
        self.height = height
        self.age = Double(age)
        self.sex = sex
        self.impedance = Double(impedance)
    }

    private func clamp(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
        if value < minimum { return minimum }
        if value > maximum { return maximum }
        return value
    }

    // Lean Body Mass Coefficient – Basis für viele andere Werte.
    func lbmCoefficient() -> Double {
        var lbm = (height * 9.058 / 100) * (height / 100)
        lbm += weight * 0.32 + 12.226
        lbm -= impedance * 0.0068
        lbm -= age * 0.0542
        return lbm
    }

    func bmi() -> Double {
        weight / pow(height / 100, 2)
    }

    func fatPercentage() -> Double {
        let const: Double
        if sex == .female && age <= 49 {
            const = 9.25
        } else if sex == .female && age > 49 {
            const = 4.95
        } else {
            const = 0.8
        }

        let lbm = lbmCoefficient()

        var coefficient: Double
        if sex == .male && weight < 61 {
            coefficient = 0.98
        } else if sex == .female && weight > 60 {
            coefficient = 0.96
            if height > 160 { coefficient *= 1.03 }
        } else if sex == .female && weight < 50 {
            coefficient = 1.02
            if height > 160 { coefficient *= 1.03 }
        } else {
            coefficient = 1.0
        }

        var fat = (1.0 - (((lbm - const) * coefficient) / weight)) * 100
        if fat > 63 { fat = 75 }
        return fat
    }

    func waterPercentage() -> Double {
        var water = (100 - fatPercentage()) * 0.7
        let coefficient = water <= 50 ? 1.02 : 0.98
        if water * coefficient >= 65 { water = 75 }
        return clamp(water * coefficient, 35, 75)
    }

    func boneMass() -> Double {
        let base = sex == .female ? 0.245691014 : 0.18016894
        var bone = (base - (lbmCoefficient() * 0.07158)) * -1

        if bone > 2.2 {
            bone += 0.1
        } else {
            bone -= 0.1
        }

        if sex == .female && bone > 5.1 {
            bone = 8
        } else if sex == .male && bone > 5.2 {
            bone = 8
        }
        return clamp(bone, 0.5, 8)
    }

    func muscleMass() -> Double {
        var muscle = weight - ((fatPercentage() * 0.01) * weight) - boneMass()
        if sex == .female && muscle >= 84 {
            muscle = 120
        } else if sex == .male && muscle >= 93.5 {
            muscle = 120
        }
        return clamp(muscle, 10, 120)
    }

    func visceralFat() -> Double {
        var vfal: Double
        if sex == .female {
            if weight > (13 - (height * 0.5)) * -1 {
                let sub = ((height * 1.45) + (height * 0.1158) * height) - 120
                let calc = weight * 500 / sub
                vfal = (calc - 6) + (age * 0.07)
            } else if weight < 65 {
                let sub = ((height * 1.45) + (height * 0.1158) * height) - weight
                let calc = weight * 460 / sub
                vfal = (calc - 6) + (age * 0.07)
            } else {
                let calc = 0.691 + (height * -0.0024) + (height * -0.0024)
                vfal = (((height * 0.027) - (calc * weight)) * -1) + (age * 0.07) - age
            }
        } else {
            if height < weight * 1.6 {
                let calc = ((height * 0.4) - (height * (height * 0.0826))) * -1
                vfal = ((weight * 305) / (calc + 48)) - 2.9 + (age * 0.15)
            } else {
                let calc = 0.765 + height * -0.0015
                vfal = (((height * 0.143) - (weight * calc)) * -1) + (16.00 * 0.15) - 5.60
            }
        }
        return clamp(vfal, 1, 50)
    }

    func bmr() -> Double {
        var value: Double
        if sex == .female {
            value = 864.6 + weight * 10.2036
            value -= height * 0.39336
            value -= age * 6.204
            if value > 2996 { value = 5000 }
        } else {
            value = 877.8 + weight * 14.916
            value -= height * 0.726
            value -= age * 8.976
            if value > 2322 { value = 5000 }
        }
        return clamp(value, 500, 10000)
    }

    func metabolicAge() -> Double {
        let value: Double
        if sex == .female {
            value = (height * -1.1165) + (weight * 1.5784) + (age * 0.4615) + (impedance * 0.0415) + 83.2548
        } else {
            value = (height * -0.7471) + (weight * 0.9161) + (age * 0.4184) + (impedance * 0.0517) + 54.2267
        }
        return clamp(value, 15, 80)
    }

    func compute() -> BodyComposition {
        BodyComposition(
            bmi: bmi(),
            fatPercent: fatPercentage(),
            waterPercent: waterPercentage(),
            boneMassKg: boneMass(),
            muscleMassKg: muscleMass(),
            visceralFat: visceralFat(),
            bmr: bmr(),
            metabolicAge: metabolicAge(),
            lbmKg: lbmCoefficient(),
            proteinPercent: proteinPercentage(),
            idealWeightKg: idealWeightKg(),
            bodyTypeKey: bodyType(),
            bodyScore: bodyScore()
        )
    }
}
