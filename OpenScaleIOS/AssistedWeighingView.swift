// SPDX-License-Identifier: GPL-3.0-or-later
//
// OpenTara – lokale Körperwaagen-App

import SwiftUI

/// Assistiertes Wiegen (Baby/Tier): kombiniertes Gewicht minus Referenzgewicht.
struct AssistedWeighingView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let unit: WeightUnit

    @State private var referenceProfileID: UUID?
    @State private var targetProfileID: UUID?
    @State private var reference: Double = 70   // in gewählter Einheit
    @State private var combined: Double = 75    // in gewählter Einheit
    @State private var date = Date()

    private var resultKg: Double {
        unit.toKg(combined) - unit.toKg(reference)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Referenzperson (allein)") {
                    Picker("Person", selection: $referenceProfileID) {
                        ForEach(store.profiles) { p in
                            Text(p.name).tag(Optional(p.id))
                        }
                    }
                    weightField("Gewicht allein", $reference)
                }

                Section("Zusammen (mit Baby/Tier)") {
                    weightField("Gewicht zusammen", $combined)
                }

                Section("Ergebnis") {
                    HStack {
                        Text("Baby/Tier wiegt").foregroundStyle(.secondary)
                        Spacer()
                        if resultKg > 0 {
                            Text(unit.format(kg: resultKg))
                                .font(.title3).fontWeight(.bold).monospacedDigit()
                        } else {
                            Text("–").foregroundStyle(.secondary)
                        }
                    }
                    if resultKg <= 0 {
                        Text("Das Gewicht zusammen muss größer sein als allein.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }

                Section("Speichern") {
                    Picker("In Profil", selection: $targetProfileID) {
                        ForEach(store.profiles) { p in
                            Text(p.name).tag(Optional(p.id))
                        }
                    }
                    DatePicker("Datum", selection: $date, in: ...Date())
                    Button {
                        save()
                    } label: {
                        Label("Als Messung speichern", systemImage: "square.and.arrow.down")
                    }
                    .disabled(resultKg <= 0 || targetProfileID == nil)
                }

                Section {
                    Text("Für ein eigenes Baby-/Tier-Profil kannst du oben rechts über das Profil-Symbol eine Person anlegen, z. B. Baby oder Hund.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Assistiert wiegen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onAppear(perform: setup)
            .onChange(of: referenceProfileID) { updateReference() }
        }
    }

    private func weightField(_ label: LocalizedStringKey, _ binding: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(unit.short, value: binding, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text(unit.short).foregroundStyle(.secondary)
        }
    }

    private func setup() {
        referenceProfileID = store.activeProfileID
        updateReference()
        targetProfileID = store.profiles.first { $0.id != referenceProfileID }?.id ?? store.activeProfileID
    }

    private func updateReference() {
        if let id = referenceProfileID, let w = store.history(for: id).first?.weightKg {
            reference = unit.fromKg(w)
        }
    }

    private func save() {
        guard resultKg > 0, let id = targetProfileID else { return }
        let m = ScaleMeasurement(
            date: date,
            weightKg: resultKg,
            impedance: nil,
            isStabilized: true,
            rawHex: "assistiert",
            comment: "Assistiert gewogen"
        )
        store.addManualMeasurement(m, for: id)
        dismiss()
    }
}
