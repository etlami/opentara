// SPDX-License-Identifier: GPL-3.0-or-later
//
// OpenTara – lokale Körperwaagen-App

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var scale = ScaleManager()

    @State private var editingProfile: UserProfile?
    @State private var editingMeasurement: ScaleMeasurement?
    @State private var pendingMeasurement: ScaleMeasurement?
    @State private var assignedInfo: String?
    @State private var showManualEntry = false
    @State private var showAssisted = false
    @State private var showSettings = false
    @State private var showRawLog = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    profilePicker
                    statusCard
                    metricsCard
                    goalCard
                    measuresCard
                    chartCard
                    statsCard
                    historyCard
                    rawLogCard
                }
                .padding()
            }
            .navigationTitle("OpenTara")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            showManualEntry = true
                        } label: {
                            Label("Manuelle Messung", systemImage: "square.and.pencil")
                        }
                        Button {
                            showAssisted = true
                        } label: {
                            Label("Assistiert wiegen (Baby/Tier)", systemImage: "scalemass")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingProfile = store.activeProfile
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
            .sheet(item: $editingProfile) { profile in
                ProfileEditView(profile: profile, unit: store.weightUnit) { updated in
                    store.addOrUpdate(updated)
                    store.setActiveProfile(updated.id)
                }
            }
            .sheet(item: $editingMeasurement) { m in
                MeasurementEditView(existing: m, unit: store.weightUnit,
                    onSave: { updated in
                        if let id = store.activeProfileID { store.updateMeasurement(updated, for: id) }
                    },
                    onDelete: {
                        if let id = store.activeProfileID { store.deleteMeasurement(m.id, for: id) }
                    })
            }
            .sheet(isPresented: $showManualEntry) {
                MeasurementEditView(existing: nil, unit: store.weightUnit, onSave: { new in
                    if let id = store.activeProfileID { store.addManualMeasurement(new, for: id) }
                })
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(store)
            }
            .sheet(isPresented: $showAssisted) {
                AssistedWeighingView(unit: store.weightUnit).environmentObject(store)
            }
            .onAppear {
                scale.onStabilizedMeasurement = { m in
                    handleMeasurement(m)
                }
            }
            .confirmationDialog("Wer wurde gewogen?",
                isPresented: Binding(get: { pendingMeasurement != nil },
                                     set: { if !$0 { pendingMeasurement = nil } }),
                titleVisibility: .visible) {
                ForEach(store.profiles) { p in
                    Button(p.name) { assignPending(to: p.id) }
                }
                Button("Verwerfen", role: .destructive) { pendingMeasurement = nil }
                Button("Abbrechen", role: .cancel) { pendingMeasurement = nil }
            } message: {
                if let m = pendingMeasurement {
                    Text("Gemessen: \(store.weightUnit.format(kg: m.weightKg))")
                }
            }
        }
    }

    // MARK: - Profilauswahl

    private var profilePicker: some View {
        HStack {
            Text("Profil").font(.headline)
            Spacer()
            Picker("Profil", selection: Binding(
                get: { store.activeProfileID ?? store.profiles.first?.id ?? UUID() },
                set: { store.setActiveProfile($0) }
            )) {
                ForEach(store.profiles) { p in
                    Text(p.name).tag(p.id)
                }
            }
            .pickerStyle(.menu)
        }
        .card()
    }

    // MARK: - Status / Scan

    private var statusCard: some View {
        VStack(spacing: 12) {
            Text(scale.statusText)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if let w = scale.lastWeightKg {
                Text(fmtW(w))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(scale.lastStabilized ? .primary : .secondary)
            }

            Button {
                scale.isScanning ? scale.stopScan() : scale.startScan()
            } label: {
                Label(scale.isScanning ? "Suche läuft – stoppen" : "Waage suchen",
                      systemImage: scale.isScanning ? "stop.circle" : "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!scale.bluetoothReady)

            if let info = assignedInfo {
                Text("→ zugeordnet: \(info)")
                    .font(.caption).foregroundStyle(.green)
            }
        }
        .card()
    }

    // MARK: - Körperwerte

    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Körperwerte").font(.headline)
                Spacer()
                if let t = weightTrend() {
                    Label(String(format: "%+.2f %@", store.weightUnit.fromKg(t.delta), store.weightUnit.short),
                          systemImage: t.delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(t.delta >= 0 ? .orange : .green)
                }
            }

            if let result = currentComposition(), let p = store.activeProfile {
                metricRow("Gewicht", fmtW(result.weight))
                metricRow("BMI", String(format: "%.1f", result.bmi),
                          level: Assessment.bmi(result.bmi),
                          note: Assessment.bmiCategory(result.bmi))

                if show("ideal") {
                    let ideal = BodyMetrics(weight: result.weight, height: p.heightCm,
                                            age: p.ageYears, sex: p.sex, impedance: 0).idealWeightKg()
                    metricRow("Ideales Gewicht", fmtW(ideal, 1))
                }

                if let c = result.comp {
                    if show("fat") {
                        metricRow("Körperfett", String(format: "%.1f %%", c.fatPercent),
                                  level: Assessment.bodyFat(c.fatPercent, sex: p.sex))
                    }
                    if show("water") {
                        metricRow("Wasser", String(format: "%.1f %%", c.waterPercent),
                                  level: Assessment.water(c.waterPercent, sex: p.sex))
                    }
                    if show("muscle") { metricRow("Muskelmasse", fmtW(c.muscleMassKg, 1)) }
                    if show("bone") { metricRow("Knochenmasse", fmtW(c.boneMassKg, 1)) }
                    if show("visceral") {
                        metricRow("Viszeralfett", String(format: "%.0f", c.visceralFat),
                                  level: Assessment.visceralFat(c.visceralFat))
                    }
                    if show("bmr") { metricRow("Grundumsatz", String(format: "%.0f kcal", c.bmr)) }
                    if show("metaage") { metricRow("Metabol. Alter", String(format: "%.0f Jahre", c.metabolicAge)) }
                    if show("protein") { metricRow("Protein", String(format: "%.1f %%", c.proteinPercent)) }
                    if show("lbm") { metricRow("Fettfreie Masse", fmtW(c.lbmKg, 1)) }
                    if show("bodytype") { metricRow("Körpertyp", bodyTypeLabel(c.bodyTypeKey)) }
                    if show("bodyscore") {
                        metricRow("Body Score", String(format: "%.0f / 100", c.bodyScore),
                                  level: scoreLevel(c.bodyScore))
                    }

                    Text("Farben = grobe Orientierung, keine medizinische Bewertung.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Für Fett/Wasser/Muskel bitte **barfuß** messen – dann kommt die Impedanz mit.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Text("Noch keine Messung. Waage suchen und draufstellen – oder oben links **+** für manuelle Eingabe.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func metricRow(_ label: String, _ value: String,
                           level: AssessmentLevel = .unknown, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).fontWeight(.semibold).monospacedDigit()
                    .foregroundStyle(level.color)
                if let note {
                    Text(note).font(.caption2)
                        .foregroundStyle(level == .unknown ? Color.secondary : level.color)
                }
            }
        }
    }

    // MARK: - Diagramm

    @ViewBuilder
    private var chartCard: some View {
        if let p = store.activeProfile, let id = store.activeProfileID {
            HistoryChartView(profile: p, measurements: store.history(for: id), unit: store.weightUnit)
        }
    }

    // MARK: - Ziel

    @ViewBuilder
    private var goalCard: some View {
        if let p = store.activeProfile, let id = store.activeProfileID, p.targetWeightKg != nil {
            GoalCardView(profile: p, history: store.history(for: id), unit: store.weightUnit)
        }
    }

    // MARK: - Umfänge & Verhältnisse

    @ViewBuilder
    private var measuresCard: some View {
        if let m = latestMeasurement(), let p = store.activeProfile,
           m.hasCircumferences || (m.comment?.isEmpty == false) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Maße & Notiz").font(.headline)

                if let w = m.waistCm {
                    metricRow("Taille", String(format: "%.1f cm", w))
                    if let whtr = m.waistToHeight(height: p.heightCm) {
                        metricRow("Taille/Größe (WHtR)", String(format: "%.2f", whtr),
                                  level: whtr < 0.5 ? .normal : .elevated)
                    }
                }
                if let h = m.hipCm { metricRow("Hüfte", String(format: "%.1f cm", h)) }
                if let whr = m.waistToHip {
                    metricRow("Taille/Hüfte (WHR)", String(format: "%.2f", whr))
                }
                if let c = m.chestCm  { metricRow("Brust", String(format: "%.1f cm", c)) }
                if let t = m.thighCm  { metricRow("Oberschenkel", String(format: "%.1f cm", t)) }
                if let b = m.bicepsCm { metricRow("Bizeps", String(format: "%.1f cm", b)) }
                if let n = m.neckCm   { metricRow("Nacken", String(format: "%.1f cm", n)) }

                if let cm = m.comment, !cm.isEmpty {
                    Divider()
                    Text(cm).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    // MARK: - Statistik

    @ViewBuilder
    private var statsCard: some View {
        let items = store.activeProfileID.map { store.history(for: $0) } ?? []
        if items.count >= 2 {
            let weights = items.map { $0.weightKg }
            let minW = weights.min() ?? 0
            let maxW = weights.max() ?? 0
            let avgW = weights.reduce(0, +) / Double(weights.count)
            VStack(alignment: .leading, spacing: 8) {
                Text("Statistik").font(.headline)
                metricRow("Messungen", "\(items.count)")
                metricRow("Minimum", fmtW(minW))
                metricRow("Maximum", fmtW(maxW))
                metricRow("Durchschnitt", fmtW(avgW))
                metricRow("Spanne", fmtW(maxW - minW))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func latestMeasurement() -> ScaleMeasurement? {
        guard let id = store.activeProfileID else { return nil }
        return store.history(for: id).first
    }

    /// Formatiert einen kg-Wert in der gewählten Einheit.
    private func fmtW(_ kg: Double, _ decimals: Int = 2) -> String {
        store.weightUnit.format(kg: kg, decimals: decimals)
    }

    /// Soll ein optionaler Wert angezeigt werden?
    private func show(_ key: String) -> Bool {
        !store.hiddenMetrics.contains(key)
    }

    /// Farbe für den Body Score (hoch = gut).
    private func scoreLevel(_ score: Double) -> AssessmentLevel {
        if score >= 80 { return .normal }
        if score >= 60 { return .elevated }
        return .high
    }

    /// Neue Messung einsortieren – automatisch oder mit Nachfrage.
    private func handleMeasurement(_ m: ScaleMeasurement) {
        guard store.autoAssign else {
            if let id = store.activeProfileID { store.recordMeasurement(m, for: id) }
            return
        }
        let match = store.bestProfileMatch(forWeightKg: m.weightKg)
        if let id = match.id, !match.ambiguous {
            store.recordMeasurement(m, for: id)
            store.setActiveProfile(id)
            assignedInfo = store.profiles.first { $0.id == id }?.name
        } else {
            pendingMeasurement = m
        }
    }

    private func assignPending(to id: UUID) {
        if let m = pendingMeasurement {
            store.recordMeasurement(m, for: id)
            store.setActiveProfile(id)
            assignedInfo = store.profiles.first { $0.id == id }?.name
        }
        pendingMeasurement = nil
    }

    // MARK: - Historie

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Verlauf").font(.headline)
            let items = store.activeProfileID.map { store.history(for: $0) } ?? []
            if items.isEmpty {
                Text("Noch keine gespeicherten Messungen.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(15)) { m in
                    Button {
                        editingMeasurement = m
                    } label: {
                        HStack {
                            Text(m.date, format: .dateTime.day().month().year().hour().minute())
                                .font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            Text(fmtW(m.weightKg)).monospacedDigit()
                            if m.impedance != nil {
                                Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.orange)
                            }
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    if m.id != items.prefix(15).last?.id { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Roh-Log (Kalibrierung)

    private var rawLogCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showRawLog.toggle()
            } label: {
                HStack {
                    Text("Roh-Daten (Kalibrierung)").font(.headline)
                    Spacer()
                    Image(systemName: showRawLog ? "chevron.up" : "chevron.down")
                }
            }
            .buttonStyle(.plain)

            if showRawLog {
                if scale.log.isEmpty {
                    Text("Noch nichts empfangen.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(scale.log.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Berechnung / Trend

    private func currentComposition() -> (weight: Double, bmi: Double, comp: BodyComposition?)? {
        guard let p = store.activeProfile else { return nil }

        let weight: Double
        let impedance: Int?
        if let w = scale.lastWeightKg {
            weight = w
            impedance = scale.lastImpedance
        } else if let last = store.history(for: p.id).first {
            weight = last.weightKg
            impedance = last.impedance
        } else {
            return nil
        }

        let bmi = weight / pow(p.heightCm / 100, 2)
        var comp: BodyComposition?
        if let imp = impedance {
            comp = BodyMetrics(weight: weight, height: p.heightCm,
                               age: p.ageYears, sex: p.sex, impedance: imp).compute()
        }
        return (weight, bmi, comp)
    }

    private func weightTrend() -> (delta: Double, up: Bool)? {
        guard let id = store.activeProfileID else { return nil }
        let h = store.history(for: id)
        guard h.count >= 2 else { return nil }
        let delta = h[0].weightKg - h[1].weightKg
        return (delta, delta >= 0)
    }
}
