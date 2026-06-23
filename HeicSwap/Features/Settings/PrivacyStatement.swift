//
//  PrivacyStatement.swift
//  HeicSwap
//
//  The literally-true privacy statement that backs the brand (task 8.1). A pure value type so the
//  copy is the single source of truth and can be checked by tests (the same pattern as
//  `OnboardingContent` / `PaywallPlan`) — it must match the App Store nutrition label (task 11.1).
//

import Foundation

/// One line of the Settings privacy section: a leading SF Symbol and an honest statement of one
/// data practice.
struct PrivacyPoint: Identifiable, Equatable {
    /// Stable index for `ForEach`.
    let id: Int
    /// SF Symbol leading the point.
    let systemImage: String
    /// The honest, no-overclaim statement.
    let text: String
}

/// The privacy statement shown in Settings — precisely true to what HeicSwap actually does, with no
/// overclaim (AC3).
///
/// HeicSwap converts entirely on-device, so photos and files never leave the iPhone. The app *does*
/// make two narrow network calls — anonymous usage analytics (TelemetryDeck) and purchase validation
/// (RevenueCat via Apple) — so the statement discloses those rather than claiming "no network at
/// all". Keep this in sync with the App Store privacy nutrition label produced at submission (11.1).
enum PrivacyStatement {

    /// The headline promise.
    static let headline = String(localized: "Your photos never leave this iPhone.")

    /// The honest, itemized data practices, in order of importance.
    static let points: [PrivacyPoint] = [
        PrivacyPoint(
            id: 0,
            systemImage: "iphone",
            text: String(localized: "Every conversion runs entirely on your device. Your photos and files are never uploaded or collected — not by us, not by anyone.")
        ),
        PrivacyPoint(
            id: 1,
            systemImage: "chart.bar.xaxis",
            text: String(localized: "We collect anonymous usage statistics to improve the app. They contain no photos, no file contents, and nothing that identifies you.")
        ),
        PrivacyPoint(
            id: 2,
            systemImage: "creditcard",
            text: String(localized: "Purchases are handled by Apple. We use RevenueCat only to confirm your subscription — it never receives your photos or files.")
        ),
    ]
}
