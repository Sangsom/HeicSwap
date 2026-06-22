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
/// host stack supplies the bar and back button. The full defaults, manage-subscription,
/// and privacy statement land in task 8.1; for now it hosts the paywall entry (task 6.2)
/// so HeicSwap Pro has a permanent, ungated home.
struct SettingsScreen: View {
    @Environment(\.entitlementStore) private var entitlementStore
    @State private var isPaywallPresented = false

    var body: some View {
        List {
            Section {
                if entitlementStore.isPro {
                    Label {
                        Text("HeicSwap Pro is active")
                            .foregroundStyle(Theme.Colors.textPrimary)
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Theme.Colors.success)
                    }
                } else {
                    Button {
                        isPaywallPresented = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                                Text("Unlock HeicSwap Pro")
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text("Unlimited batches, resize to size, strip metadata")
                                    .font(Theme.Typography.footnote)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        } icon: {
                            Image(systemName: "lock.open.fill")
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    .accessibilityHint(Text(String(localized: "Opens the HeicSwap Pro paywall")))
                }
            }
            .listRowBackground(Theme.Colors.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .sheet(isPresented: $isPaywallPresented) {
            PaywallSheet()
        }
    }
}

#Preview {
    NavigationStack {
        SettingsScreen()
    }
}
