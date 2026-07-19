// SPDX-License-Identifier: GPL-3.0-or-later
//
// Freescale – lokale Körperwaagen-App

import SwiftUI
import UniformTypeIdentifiers

/// CSV-Datei zum Export/Import über die iOS-Dateiauswahl.
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }

    var text: String
    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Wandelt Messungen in CSV um und wieder zurück. Gewicht immer in kg.
enum CSVFormatter {
    static let header = "date,weight_kg,impedance,comment,waist_cm,hip_cm,chest_cm,thigh_cm,biceps_cm,neck_cm"
    private static let iso = ISO8601DateFormatter()

    // MARK: Export

    static func export(_ measurements: [ScaleMeasurement]) -> String {
        var lines = [header]
        for m in measurements.sorted(by: { $0.date < $1.date }) {
            let fields = [
                iso.string(from: m.date),
                String(m.weightKg),
                m.impedance.map(String.init) ?? "",
                m.comment ?? "",
                num(m.waistCm), num(m.hipCm), num(m.chestCm),
                num(m.thighCm), num(m.bicepsCm), num(m.neckCm),
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func num(_ v: Double?) -> String { v.map { String($0) } ?? "" }

    private static func escape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    // MARK: Import

    static func parse(_ text: String) -> [ScaleMeasurement] {
        var result: [ScaleMeasurement] = []
        for (i, f) in splitRows(text).enumerated() {
            if i == 0 && f.first?.lowercased() == "date" { continue }   // Kopfzeile
            guard f.count >= 2, let date = iso.date(from: f[0]), let weight = Double(f[1]) else { continue }
            func d(_ idx: Int) -> Double? { idx < f.count ? Double(f[idx]) : nil }
            result.append(ScaleMeasurement(
                date: date,
                weightKg: weight,
                impedance: f.count > 2 ? Int(f[2]) : nil,
                isStabilized: true,
                rawHex: "importiert",
                comment: (f.count > 3 && !f[3].isEmpty) ? f[3] : nil,
                waistCm: d(4), hipCm: d(5), chestCm: d(6),
                thighCm: d(7), bicepsCm: d(8), neckCm: d(9)
            ))
        }
        return result
    }

    /// Minimaler CSV-Parser mit Anführungszeichen-Unterstützung.
    private static func splitRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var record: [String] = []
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                record.append(field); field = ""
            } else if c.isNewline {
                record.append(field); field = ""
                if !(record.count == 1 && record[0].isEmpty) { rows.append(record) }
                record = []
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            if !(record.count == 1 && record[0].isEmpty) { rows.append(record) }
        }
        return rows
    }
}
