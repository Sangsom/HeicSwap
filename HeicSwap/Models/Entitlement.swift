//
//  Entitlement.swift
//  HeicSwap
//
//  The app-domain representation of what the user has unlocked. The purchase layer
//  (`PurchaseClient`, task 6.x) maps RevenueCat state onto this; feature code and the
//  value-gate (task 2.2) read it without knowing about the store.
//

import Foundation

/// What the user has unlocked. Deliberately a closed two-case enum: the app is either on
/// the free tier or has Pro. Pro-ness lives here — never on `OutputFormat`.
nonisolated enum Entitlement: Sendable, Equatable, Hashable, CaseIterable {
    /// Default tier: basic conversion plus small PDFs (see `FREE_BATCH_LIMIT`, task 2.2).
    case free
    /// Unlocks large batches, resize-to-target-size, and metadata stripping.
    case pro

    /// Convenience for gating checks.
    var isPro: Bool { self == .pro }
}
