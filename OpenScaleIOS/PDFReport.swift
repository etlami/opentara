// SPDX-License-Identifier: GPL-3.0-or-later
//
// Freescale – lokale Körperwaagen-App

import UIKit

/// Erzeugt einen einfachen PDF-Gewichtsbericht (A4) für Arzt/Unterlagen.
enum PDFReport {
    static func generate(profile: UserProfile,
                         measurements: [ScaleMeasurement],
                         unit: WeightUnit) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)  // A4 in Punkten
        let margin: CGFloat = 40
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let titleFont = UIFont.boldSystemFont(ofSize: 20)
        let subFont = UIFont.systemFont(ofSize: 11)
        let headFont = UIFont.boldSystemFont(ofSize: 11)
        let rowFont = UIFont.systemFont(ofSize: 11)

        let cols: [(String, CGFloat)] = [
            ("Datum", margin),
            ("Gewicht", margin + 160),
            ("BMI", margin + 270),
            ("Körperfett", margin + 350),
        ]

        let df = DateFormatter()
        df.dateFormat = "dd.MM.yyyy HH:mm"

        return renderer.pdfData { ctx in
            var y: CGFloat = margin
            ctx.beginPage()

            "Freescale – Gewichtsbericht".draw(
                at: CGPoint(x: margin, y: y), withAttributes: [.font: titleFont])
            y += 28

            let created = Date().formatted(date: .abbreviated, time: .shortened)
            let sub = "\(profile.name) · Größe \(Int(profile.heightCm)) cm · \(profile.sex.localized) · erstellt \(created)"
            sub.draw(at: CGPoint(x: margin, y: y),
                     withAttributes: [.font: subFont, .foregroundColor: UIColor.darkGray])
            y += 26

            func drawHeader() {
                for (text, x) in cols {
                    text.draw(at: CGPoint(x: x, y: y), withAttributes: [.font: headFont])
                }
                y += 16
                let line = UIBezierPath()
                line.move(to: CGPoint(x: margin, y: y))
                line.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
                UIColor.lightGray.setStroke()
                line.stroke()
                y += 6
            }
            drawHeader()

            for m in measurements.sorted(by: { $0.date > $1.date }) {
                if y > pageRect.height - margin - 16 {
                    ctx.beginPage()
                    y = margin
                    drawHeader()
                }
                let bmi = m.weightKg / pow(profile.heightCm / 100, 2)
                var fat = "–"
                if let imp = m.impedance {
                    let f = BodyMetrics(weight: m.weightKg, height: profile.heightCm,
                                        age: profile.ageYears, sex: profile.sex, impedance: imp).fatPercentage()
                    fat = String(format: "%.1f %%", f)
                }
                let values = [
                    df.string(from: m.date),
                    unit.format(kg: m.weightKg),
                    String(format: "%.1f", bmi),
                    fat,
                ]
                for (i, col) in cols.enumerated() {
                    values[i].draw(at: CGPoint(x: col.1, y: y), withAttributes: [.font: rowFont])
                }
                y += 16
            }
        }
    }
}
