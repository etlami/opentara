// SPDX-License-Identifier: GPL-3.0-or-later
//
// Freescale – lokale Körperwaagen-App

import SwiftUI

/// Einheitlicher Karten-Hintergrund für alle Ansichten.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}
