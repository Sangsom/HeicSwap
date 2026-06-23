//
//  Haptics.swift
//  HeicSwap
//
//  Centralized haptic feedback (task 10.2). The design spec (§4) names a haptic for each key
//  moment; this maps those names to the right system generator so the policy lives in one place and
//  call sites read as intent ("conversion complete") rather than mechanism ("notification .success").
//

import UIKit

/// The app's haptic vocabulary, from the design spec's Haptics table:
///
/// | Moment | Haptic |
/// |---|---|
/// | Conversion complete | `.success` |
/// | Format / option chip selected | `.selection` |
/// | Convert tapped | `.impact(.medium)` |
/// | Remove all / destructive | `.warning` |
/// | Hit free cap (paywall) | `.impact(.rigid)` |
///
/// System haptics already honor the device's *System Haptics* setting — a user who turns them off
/// feels none of these — so there's no extra gating to do here. UIKit's generators are main-actor
/// bound; every call site (the Convert view model and the SwiftUI views) is already on the main
/// actor, so the isolation is free.
@MainActor
enum Haptics {

    /// A batch finished converting — the signature payoff moment.
    static func conversionComplete() { notify(.success) }

    /// Outputs were saved to the photo library successfully.
    static func saved() { notify(.success) }

    /// A save to the photo library failed.
    static func saveFailed() { notify(.error) }

    /// A destructive action landed — clearing the whole queue.
    static func destructive() { notify(.warning) }

    /// A selectable chip (format, resize mode, value preset) was chosen.
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }

    /// The Convert CTA fired and a run is starting.
    static func convertTapped() { impact(.medium) }

    /// A free user hit the value gate and the paywall is about to appear.
    static func freeCapHit() { impact(.rigid) }

    // MARK: - Primitives

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
