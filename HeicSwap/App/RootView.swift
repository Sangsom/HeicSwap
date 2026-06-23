//
//  RootView.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 22/06/2026.
//

import SwiftUI

/// The app's root: the Convert screen, with first-run onboarding presented over it exactly once
/// (task 7.1).
///
/// `ConvertView` is always the base, so when onboarding finishes (or is skipped) the cover dismisses
/// straight onto the usable Convert empty state — no extra navigation, no flash of a loading screen.
/// The `hasOnboarded` flag is persisted in `AppStorage`, so a second launch goes straight to Convert.
struct RootView: View {
    let convertViewModel: ConvertViewModel

    @AppStorage(Onboarding.hasOnboardedKey) private var hasOnboarded = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ConvertView(viewModel: convertViewModel)
            .fullScreenCover(isPresented: isOnboardingPresented) {
                OnboardingView()
            }
            // Reclaim disposable temp files as soon as the app leaves the foreground (task 10.3).
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    convertViewModel.applicationDidEnterBackground()
                }
            }
    }

    /// Presents onboarding while it hasn't been seen; flipping `hasOnboarded` from inside the cover
    /// drives the dismissal, so this binding's setter only mirrors that state.
    private var isOnboardingPresented: Binding<Bool> {
        Binding(
            get: { !hasOnboarded },
            set: { hasOnboarded = !$0 }
        )
    }
}
