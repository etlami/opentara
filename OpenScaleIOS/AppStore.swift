// SPDX-License-Identifier: GPL-3.0-or-later
//
// Freescale – lokale Körperwaagen-App

import Foundation
import Combine

/// Hält Profile + Messhistorie und speichert sie in UserDefaults.
final class AppStore: ObservableObject {

    @Published var profiles: [UserProfile] = []
    @Published var activeProfileID: UUID?
    @Published private var measurements: [UUID: [ScaleMeasurement]] = [:]
    @Published var weightUnit: WeightUnit = .kg
    @Published var hiddenMetrics: Set<String> = []
    @Published var autoAssign: Bool = true
    @Published var reminderEnabled: Bool = false
    @Published var reminderHour: Int = 8
    @Published var reminderMinute: Int = 0

    private let profilesKey = "openscale.profiles.v1"
    private let activeKey = "openscale.active.v1"
    private let measurementsKey = "openscale.measurements.v1"
    private let unitKey = "openscale.unit.v1"
    private let hiddenKey = "openscale.hidden.v1"
    private let autoAssignKey = "openscale.autoassign.v1"
    private let reminderEnabledKey = "openscale.reminderOn.v1"
    private let reminderHourKey = "openscale.reminderHour.v1"
    private let reminderMinuteKey = "openscale.reminderMinute.v1"

    init() {
        load()
        if profiles.isEmpty {
            let p1 = UserProfile(name: "Person 1", heightCm: 178, birthDate: defaultBirthDate(), sex: .male)
            let p2 = UserProfile(name: "Person 2", heightCm: 168, birthDate: defaultBirthDate(), sex: .female)
            profiles = [p1, p2]
            activeProfileID = p1.id
            save()
        }
        if activeProfileID == nil || !profiles.contains(where: { $0.id == activeProfileID }) {
            activeProfileID = profiles.first?.id
        }
    }

    var activeProfile: UserProfile? {
        if let id = activeProfileID { return profiles.first { $0.id == id } }
        return profiles.first
    }

    func setActiveProfile(_ id: UUID) {
        activeProfileID = id
        save()
    }

    func addOrUpdate(_ profile: UserProfile) {
        var p = profile
        let old = profiles.first(where: { $0.id == p.id })

        if let target = p.targetWeightKg {
            // Ziel neu gesetzt oder geändert -> Datum der Zielsetzung merken.
            if old?.targetWeightKg != target || p.goalSetDate == nil {
                p.goalSetDate = Date()
            }
        } else {
            p.goalSetDate = nil
        }

        if let idx = profiles.firstIndex(where: { $0.id == p.id }) {
            profiles[idx] = p
        } else {
            profiles.append(p)
        }
        save()
    }

    func deleteProfile(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        measurements[id] = nil
        if activeProfileID == id { activeProfileID = profiles.first?.id }
        save()
    }

    func recordMeasurement(_ m: ScaleMeasurement, for profileID: UUID) {
        var list = measurements[profileID] ?? []
        // Doppel-Speicherungen bei mehreren stabilen Paketen vermeiden.
        if let last = list.first,
           abs(last.weightKg - m.weightKg) < 0.05,
           m.date.timeIntervalSince(last.date) < 30 {
            list[0] = m
        } else {
            list.insert(m, at: 0)
        }
        measurements[profileID] = list
        save()
    }

    func history(for profileID: UUID) -> [ScaleMeasurement] {
        (measurements[profileID] ?? []).sorted { $0.date > $1.date }
    }

    func addManualMeasurement(_ m: ScaleMeasurement, for profileID: UUID) {
        var list = measurements[profileID] ?? []
        list.append(m)
        measurements[profileID] = list
        save()
    }

    func updateMeasurement(_ m: ScaleMeasurement, for profileID: UUID) {
        guard var list = measurements[profileID],
              let idx = list.firstIndex(where: { $0.id == m.id }) else { return }
        list[idx] = m
        measurements[profileID] = list
        save()
    }

    func deleteMeasurement(_ id: UUID, for profileID: UUID) {
        guard var list = measurements[profileID] else { return }
        list.removeAll { $0.id == id }
        measurements[profileID] = list
        save()
    }

    /// Importiert Messungen, überspringt exakte Duplikate (gleiches Datum + Gewicht).
    /// Gibt die Anzahl tatsächlich hinzugefügter Messungen zurück.
    @discardableResult
    func importMeasurements(_ list: [ScaleMeasurement], for profileID: UUID) -> Int {
        var existing = measurements[profileID] ?? []
        var added = 0
        for m in list {
            let dup = existing.contains {
                abs($0.date.timeIntervalSince(m.date)) < 1 && abs($0.weightKg - m.weightKg) < 0.001
            }
            if !dup { existing.append(m); added += 1 }
        }
        measurements[profileID] = existing
        if added > 0 { save() }
        return added
    }

    func setWeightUnit(_ u: WeightUnit) {
        weightUnit = u
        save()
    }

    func setAutoAssign(_ v: Bool) {
        autoAssign = v
        save()
    }

    /// Erwartetes Gewicht eines Profils = letztes gespeichertes Gewicht.
    func expectedWeight(for profileID: UUID) -> Double? {
        history(for: profileID).first?.weightKg
    }

    /// Findet das Profil mit dem am besten passenden Gewicht.
    /// `ambiguous == true`, wenn die Zuordnung unsicher ist (dann nachfragen).
    func bestProfileMatch(forWeightKg weight: Double) -> (id: UUID?, ambiguous: Bool) {
        if profiles.count <= 1 { return (profiles.first?.id, false) }

        let candidates = profiles.compactMap { p -> (UUID, Double)? in
            expectedWeight(for: p.id).map { (p.id, abs($0 - weight)) }
        }.sorted { $0.1 < $1.1 }

        guard let best = candidates.first else { return (nil, true) }  // keine Historie

        let confident = best.1 <= 5                                    // < 5 kg Abweichung
        let secondClose = candidates.count >= 2 && (candidates[1].1 - best.1) < 3
        let someUnknown = candidates.count < profiles.count            // Profil ohne Historie

        if confident && !secondClose && !someUnknown {
            return (best.0, false)
        }
        return (best.0, true)
    }

    func setMetric(_ key: String, hidden: Bool) {
        if hidden { hiddenMetrics.insert(key) } else { hiddenMetrics.remove(key) }
        save()
    }

    // MARK: - Persistenz

    private func save() {
        let d = UserDefaults.standard
        let enc = JSONEncoder()
        if let p = try? enc.encode(profiles) { d.set(p, forKey: profilesKey) }
        if let m = try? enc.encode(measurements) { d.set(m, forKey: measurementsKey) }
        if let id = activeProfileID { d.set(id.uuidString, forKey: activeKey) }
        d.set(weightUnit.rawValue, forKey: unitKey)
        if let h = try? enc.encode(Array(hiddenMetrics)) { d.set(h, forKey: hiddenKey) }
        d.set(autoAssign, forKey: autoAssignKey)
        d.set(reminderEnabled, forKey: reminderEnabledKey)
        d.set(reminderHour, forKey: reminderHourKey)
        d.set(reminderMinute, forKey: reminderMinuteKey)
    }

    private func load() {
        let d = UserDefaults.standard
        let dec = JSONDecoder()
        if let data = d.data(forKey: profilesKey),
           let p = try? dec.decode([UserProfile].self, from: data) {
            profiles = p
        }
        if let data = d.data(forKey: measurementsKey),
           let m = try? dec.decode([UUID: [ScaleMeasurement]].self, from: data) {
            measurements = m
        }
        if let s = d.string(forKey: activeKey), let id = UUID(uuidString: s) {
            activeProfileID = id
        }
        if let u = d.string(forKey: unitKey), let unit = WeightUnit(rawValue: u) {
            weightUnit = unit
        }
        if let data = d.data(forKey: hiddenKey),
           let arr = try? dec.decode([String].self, from: data) {
            hiddenMetrics = Set(arr)
        }
        if d.object(forKey: autoAssignKey) != nil {
            autoAssign = d.bool(forKey: autoAssignKey)
        }
        reminderEnabled = d.bool(forKey: reminderEnabledKey)
        if d.object(forKey: reminderHourKey) != nil { reminderHour = d.integer(forKey: reminderHourKey) }
        if d.object(forKey: reminderMinuteKey) != nil { reminderMinute = d.integer(forKey: reminderMinuteKey) }
    }

    func setReminder(enabled: Bool, hour: Int, minute: Int) {
        reminderEnabled = enabled
        reminderHour = hour
        reminderMinute = minute
        save()
    }
}
