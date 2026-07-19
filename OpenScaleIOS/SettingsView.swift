// SPDX-License-Identifier: GPL-3.0-or-later
//
// Freescale – lokale Körperwaagen-App

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var exporting = false
    @State private var importing = false
    @State private var exportDoc: CSVDocument?
    @State private var importMessage: String?

    @State private var reminderOn = false
    @State private var reminderTime = Date()
    @State private var reminderDenied = false

    @State private var pdfURL: URL?
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Einheit") {
                    Picker("Gewicht", selection: Binding(
                        get: { store.weightUnit },
                        set: { store.setWeightUnit($0) }
                    )) {
                        ForEach(WeightUnit.allCases) { u in
                            Text(u.label).tag(u)
                        }
                    }
                }

                Section("Angezeigte Werte") {
                    ForEach(MetricCatalog.optional, id: \.key) { metric in
                        Toggle(metric.label, isOn: Binding(
                            get: { !store.hiddenMetrics.contains(metric.key) },
                            set: { store.setMetric(metric.key, hidden: !$0) }
                        ))
                    }
                }

                Section("Automatik") {
                    Toggle("Automatische Personen-Zuordnung", isOn: Binding(
                        get: { store.autoAssign },
                        set: { store.setAutoAssign($0) }
                    ))
                    Text("Ordnet eine Messung automatisch der Person mit dem am besten passenden Gewicht zu. Bei Unklarheit fragt die App nach.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Erinnerung") {
                    Toggle("Tägliche Wiege-Erinnerung", isOn: $reminderOn)
                    if reminderOn {
                        DatePicker("Uhrzeit", selection: $reminderTime,
                                   displayedComponents: .hourAndMinute)
                    }
                }

                Section("Daten (aktuelles Profil)") {
                    Button {
                        if let id = store.activeProfileID {
                            exportDoc = CSVDocument(text: CSVFormatter.export(store.history(for: id)))
                            exporting = true
                        }
                    } label: {
                        Label("Exportieren (CSV)", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("Importieren (CSV)", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        makePDF()
                    } label: {
                        Label("PDF-Bericht (für Arzt)", systemImage: "doc.richtext")
                    }
                }

                Section("Unterstützte Waagen") {
                    ForEach(Array(ScaleDriverRegistry.all.enumerated()), id: \.offset) { _, d in
                        HStack {
                            Text(d.displayName).font(.footnote)
                            Spacer()
                            Text(d.isTested ? "getestet" : "experimentell")
                                .font(.caption2)
                                .foregroundStyle(d.isTested ? .green : .orange)
                        }
                    }
                }

                Section {
                    Text("Gewicht/BMI werden immer angezeigt. Fett, Wasser & Co. nur, wenn barfuß (Impedanz) gemessen wurde. Der CSV-Export speichert Gewicht immer in kg. Experimentell bedeutet: Treiber ist portiert, aber noch nicht mit echter Hardware bestätigt.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .fileExporter(isPresented: $exporting,
                          document: exportDoc,
                          contentType: .commaSeparatedText,
                          defaultFilename: exportFilename()) { _ in }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                handleImport(result)
            }
            .alert("Import", isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )) {
                Button("OK") { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
            .alert("Benachrichtigungen aus", isPresented: $reminderDenied) {
                Button("OK") { }
            } message: {
                Text("Erinnerungen sind für Freescale deaktiviert. Bitte in den iOS-Einstellungen unter Mitteilungen erlauben.")
            }
            .onAppear(perform: loadReminder)
            .onChange(of: reminderOn) { applyReminder() }
            .onChange(of: reminderTime) { if reminderOn { applyReminder() } }
            .sheet(isPresented: $showShare) {
                if let u = pdfURL { ShareSheet(items: [u]) }
            }
        }
    }

    private func makePDF() {
        guard let id = store.activeProfileID, let p = store.activeProfile else { return }
        let data = PDFReport.generate(profile: p,
                                      measurements: store.history(for: id),
                                      unit: store.weightUnit)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Freescale-Bericht.pdf")
        try? data.write(to: url)
        pdfURL = url
        showShare = true
    }

    private func loadReminder() {
        reminderOn = store.reminderEnabled
        var c = DateComponents()
        c.hour = store.reminderHour
        c.minute = store.reminderMinute
        reminderTime = Calendar.current.date(from: c) ?? Date()
    }

    private func applyReminder() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let hour = comps.hour ?? 8
        let minute = comps.minute ?? 0
        store.setReminder(enabled: reminderOn, hour: hour, minute: minute)

        if reminderOn {
            ReminderManager.requestAuthorization { granted in
                if granted {
                    ReminderManager.schedule(hour: hour, minute: minute)
                } else {
                    reminderOn = false
                    store.setReminder(enabled: false, hour: hour, minute: minute)
                    reminderDenied = true
                }
            }
        } else {
            ReminderManager.cancel()
        }
    }

    private func exportFilename() -> String {
        let name = store.activeProfile?.name ?? "profil"
        let safe = name.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "-")
        return "freescale-\(safe.isEmpty ? "profil" : safe)"
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result, let id = store.activeProfileID else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            importMessage = "Datei konnte nicht gelesen werden."
            return
        }
        let text = String(decoding: data, as: UTF8.self)
        let parsed = CSVFormatter.parse(text)
        let added = store.importMeasurements(parsed, for: id)
        importMessage = added > 0
            ? "\(added) Messung(en) importiert."
            : "Keine neuen Messungen (Datei leer oder alles schon vorhanden)."
    }
}
