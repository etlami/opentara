// SPDX-License-Identifier: GPL-3.0-or-later
//
// Freescale – lokale Körperwaagen-App

import SwiftUI

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: UserProfile
    @State private var targetText: String
    let unit: WeightUnit
    let onSave: (UserProfile) -> Void

    init(profile: UserProfile?, unit: WeightUnit = .kg, onSave: @escaping (UserProfile) -> Void) {
        let p = profile ?? UserProfile(name: "Neue Person", heightCm: 175,
                                       birthDate: defaultBirthDate(), sex: .male)
        _draft = State(initialValue: p)
        _targetText = State(initialValue: p.targetWeightKg.map { String(format: "%g", unit.fromKg($0)) } ?? "")
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
                        d.targetWeightKg = num(targetText).map { unit.toKg($0) }
                        onSave(d)
                        dismiss()
                    }
                }
            }
        }
    }
}
