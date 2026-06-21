//
//  ConvertView.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 21/06/2026.
//

import SwiftUI

/// The root of the app — a `NavigationStack` hosting the Convert screen.
///
/// This is the shell skeleton (task 4.1): a serif title, the persistent on-device
/// trust badge, an empty-state placeholder, and a Settings entry in the nav bar.
/// The queue, options, and convert flow land in Phase 5 and slot into `content`;
/// new pushable screens add a case to `ConvertRoute`.
struct ConvertView: View {
    @State private var path: [ConvertRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            path.append(.settings)
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
                .navigationDestination(for: ConvertRoute.self) { route in
                    switch route {
                    case .settings:
                        SettingsScreen()
                    }
                }
        }
    }

    private var content: some View {
        ZStack {
            Theme.Colors.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                header

                EmptyStateView(
                    icon: "photo.on.rectangle.angled",
                    title: String(localized: "No photos yet"),
                    message: String(localized: "Add photos to convert, resize, or turn into a PDF — all on your device.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.section)
            .padding(.top, Theme.Spacing.section)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            OnDeviceBadge()

            Text("Convert")
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }
}

/// Type-safe push destinations for the Convert stack. Phase 5 extends this.
enum ConvertRoute: Hashable {
    case settings
}

#Preview("Light") {
    ConvertView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ConvertView()
        .preferredColorScheme(.dark)
}
