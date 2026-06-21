//
//  SettingsScreen.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 23/02/2026.
//

import SwiftUI

/// Placeholder Settings screen, pushed onto the Convert stack from the nav bar.
///
/// Intentionally owns no `NavigationStack` — it's a pushed destination, so the
/// host stack supplies the bar and back button. The real defaults, restore/manage,
/// and privacy statement land in task 8.1.
struct SettingsScreen: View {
    var body: some View {
        List {
            Section {
                Text("Settings placeholder")
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsScreen()
    }
}
