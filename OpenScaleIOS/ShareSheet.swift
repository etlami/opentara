// SPDX-License-Identifier: GPL-3.0-or-later
//
// OpenTara – lokale Körperwaagen-App

import SwiftUI
import UIKit

/// Systemweiter Teilen-Dialog (Mail, AirDrop, Drucken, In Dateien sichern …).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
