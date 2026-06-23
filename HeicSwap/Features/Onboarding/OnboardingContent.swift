//
//  OnboardingContent.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 22/06/2026.
//

import Foundation

/// One paged onboarding screen — a pure value type so the copy and ordering are testable
/// without rendering the UI (the same pattern as `PaywallPlan` / `OptionsSummary`).
struct OnboardingPage: Identifiable, Equatable {
    /// Stable index used for `TabView` selection and the page indicator.
    let id: Int
    /// SF Symbol leading the screen.
    let systemImage: String
    /// The serif value line (design requirement: "serif value lines").
    let headline: String
    /// Supporting copy beneath the headline.
    let body: String
}

/// The onboarding content + persistence key — the single source of truth for the first-run flow
/// (task 7.1). Kept free of SwiftUI so it can be unit-tested.
enum Onboarding {

    /// `AppStorage` key that records the user has seen (or skipped) onboarding, so it shows exactly
    /// once across launches (AC3). Persisted in `UserDefaults.standard`.
    static let hasOnboardedKey = "hasOnboarded"

    /// The three first-run screens, in order: value → privacy ("never uploaded") → add photos.
    /// At most three per the design (≤3 skippable screens).
    static let pages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            systemImage: "wand.and.stars",
            headline: String(localized: "Convert any photo in a tap"),
            body: String(localized: "Turn iPhone HEIC into JPG, PNG, or PDF — resize and compress without losing a thing.")
        ),
        OnboardingPage(
            id: 1,
            systemImage: "lock.shield.fill",
            headline: String(localized: "Your photos are never uploaded"),
            body: String(localized: "Every conversion happens right here on your iPhone. No servers, no account — your photos never leave the device.")
        ),
        OnboardingPage(
            id: 2,
            systemImage: "photo.badge.plus",
            headline: String(localized: "Start with your photos"),
            body: String(localized: "Add them from your library or Files. They’re processed on-device, then yours to save or share.")
        ),
    ]
}
