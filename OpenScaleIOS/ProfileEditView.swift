// SPDX-License-Identifier: GPL-3.0-or-later
//
// OpenTara – lokale Körperwaagen-App

import SwiftUI

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: UserProfile
    @State private var targetText: String
    @State private var goalDate: Date
    let unit: WeightUnit
    let onSave: (UserProfile) -> Void

    init(profile: UserProfile?, unit: WeightUnit = .kg, onSave: @escaping (UserProfile) -> Void) {
        let p = profile ?? UserProfile(name: "Neue Person", heightCm: 175,
                                       birthDate: defaultBirthDate(), sex: .male)
        _draft = State(initialValue: p)
        _targetText = State(initialValue: p.targetWeightKg.map { String(format: "%g", unit.fromKg($0)) } ?? "")
        _goalDate = State(initialValue: p.goalSetDate ?? Date())
        self.unit = unit
        self.onSave = onSave
    }

    private func num(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profil") {
                    TextField("Name", text: $draft.name)

                    HStack {
                        Text("Größe")
                        Spacer()
                        TextField("cm", value: $draft.heightCm, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("cm").foregroundStyle(.secondary)
                    }

                    DatePicker("Geburtsdatum", selection: $draft.birthDate,
                               in: ...Date(), displayedComponents: .date)

                    Picker("Geschlecht", selection: $draft.sex) {
                        ForEach(Sex.allCases) { s in
                            Text(s.localized).tag(s)
                        }
                    }
                }

                Section("Ziel (optional)") {
                    HStack {
                        Text("Zielgewicht")
                        Spacer()
                        TextField("–", text: $targetText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(unit.short).foregroundStyle(.secondary)
                    }
                    if num(targetText) != nil {
                        DatePicker("Ziel gesetzt am", selection: $goalDate,
                                   in: ...Date(), displayedComponents: .date)
                        Text("Der Fortschritt wird ab deinem Gewicht an diesem Tag berechnet.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("Alter: \(draft.ageYears) Jahre")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profil bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        var d = draft
                        if let t = num(targetText) {
                            d.targetWeightKg = unit.toKg(t)
                            d.goalSetDate = goalDate
                        } else {
                            d.targetWeightKg = nil
                            d.goalSetDate = nil
                        }
                        onSave(d)
                        dismiss()
                    }
                }
            }
        }
    }
}
