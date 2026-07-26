// SPDX-License-Identifier: GPL-3.0-or-later
//
// OpenTara – lokale Körperwaagen-App

import SwiftUI

/// Bearbeiten einer vorhandenen Messung oder manuelles Anlegen einer neuen.
struct MeasurementEditView: View {
    @Environment(\.dismiss) private var dismiss

    let existing: ScaleMeasurement?
    let unit: WeightUnit
    let profile: UserProfile?
    let onSave: (ScaleMeasurement) -> Void
    let onDelete: (() -> Void)?

    @State private var weight: Double
    @State private var date: Date
    @State private var impedanceText: String
    @State private var comment: String

    @State private var waist: String
    @State private var hip: String
    @State private var chest: String
    @State private var thigh: String
    @State private var biceps: String
    @State private var neck: String

    init(existing: ScaleMeasurement?,
         unit: WeightUnit = .kg,
         profile: UserProfile? = nil,
         onSave: @escaping (ScaleMeasurement) -> Void,
         onDelete: (() -> Void)? = nil) {
        self.existing = existing
        self.unit = unit
        self.profile = profile
        self.onSave = onSave
        self.onDelete = onDelete
        _weight = State(initialValue: unit.fromKg(existing?.weightKg ?? 70))
        _date = State(initialValue: existing?.date ?? Date())
        _impedanceText = State(initialValue: existing?.impedance.map(String.init) ?? "")
        _comment = State(initialValue: existing?.comment ?? "")
        _waist  = State(initialValue: MeasurementEditView.str(existing?.waistCm))
        _hip    = State(initialValue: MeasurementEditView.str(existing?.hipCm))
        _chest  = State(initialValue: MeasurementEditView.str(existing?.chestCm))
        _thigh  = State(initialValue: MeasurementEditView.str(existing?.thighCm))
        _biceps = State(initialValue: MeasurementEditView.str(existing?.bicepsCm))
        _neck   = State(initialValue: MeasurementEditView.str(existing?.neckCm))
    }

    private var isNew: Bool { existing == nil }

    private static func str(_ v: Double?) -> String {
        guard let v else { return "" }
        return String(format: "%g", v)
    }

    private func num(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    /// Körperwerte dieser Messung – live aus Gewicht + Impedanz + Profil berechnet.
    private var liveComposition: BodyComposition? {
        guard let p = profile,
              let imp = Int(impedanceText.trimmingCharacters(in: .whitespaces)), imp > 0 else { return nil }
        return BodyMetrics(weight: unit.toKg(weight), height: p.heightCm,
                           age: p.ageYears, sex: p.sex, impedance: imp).compute()
    }

    private func detailRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Messung") {
                    HStack {
                        Text("Gewicht")
                        Spacer()
                        TextField(unit.short, value: $weight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(unit.short).foregroundStyle(.secondary)
                    }
                    DatePicker("Datum", selection: $date, in: ...Date())
                    HStack {
                        Text("Impedanz")
                        Spacer()
                        TextField("optional", text: $impedanceText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("Ω").foregroundStyle(.secondary)
                    }
                }

                if let c = liveComposition {
                    Section("Körperwerte") {
                        detailRow("Körperfett", String(format: "%.1f %%", c.fatPercent))
                        detailRow("Wasser", String(format: "%.1f %%", c.waterPercent))
                        detailRow("Muskelmasse", unit.format(kg: c.muscleMassKg, decimals: 1))
                        detailRow("Knochenmasse", unit.format(kg: c.boneMassKg, decimals: 1))
                        detailRow("Viszeralfett", String(format: "%.0f", c.visceralFat))
                        detailRow("Grundumsatz", String(format: "%.0f kcal", c.bmr))
                        detailRow("Metabol. Alter", String(format: "%.0f Jahre", c.metabolicAge))
                        detailRow("Protein", String(format: "%.1f %%", c.proteinPercent))
                        detailRow("Fettfreie Masse", unit.format(kg: c.lbmKg, decimals: 1))
                        detailRow("Körpertyp", bodyTypeLabel(c.bodyTypeKey))
                        detailRow("Body Score", String(format: "%.0f / 100", c.bodyScore))
                    }
                }

                Section("Umfänge (optional, cm)") {
                    circumferenceField("Taille", $waist)
                    circumferenceField("Hüfte", $hip)
                    circumferenceField("Brust", $chest)
                    circumferenceField("Oberschenkel", $thigh)
                    circumferenceField("Bizeps", $biceps)
                    circumferenceField("Nacken", $neck)
                }

                Section("Notiz") {
                    TextField("Kommentar", text: $comment, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    Text("Impedanz nur ausfüllen, wenn bekannt – sie wird für Fett/Wasser/Muskel gebraucht. Ohne Impedanz gibt es nur Gewicht + BMI.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if !isNew, let onDelete {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("Messung löschen", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Neue Messung" : "Messung bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                }
            }
        }
    }

    private func circumferenceField(_ label: LocalizedStringKey, _ binding: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("–", text: binding)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text("cm").foregroundStyle(.secondary)
        }
    }

    private func save() {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = ScaleMeasurement(
            id: existing?.id ?? UUID(),
            date: date,
            weightKg: unit.toKg(weight),
            impedance: Int(impedanceText.trimmingCharacters(in: .whitespaces)),
            isStabilized: existing?.isStabilized ?? true,
            rawHex: existing?.rawHex ?? "manuell",
            comment: trimmed.isEmpty ? nil : trimmed,
            waistCm: num(waist),
            hipCm: num(hip),
            chestCm: num(chest),
            thighCm: num(thigh),
            bicepsCm: num(biceps),
            neckCm: num(neck)
        )
        onSave(m)
        dismiss()
    }
}
