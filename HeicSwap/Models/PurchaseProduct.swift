//
//  PurchaseProduct.swift
//  HeicSwap
//
//  The app-domain representation of a purchasable Pro product. `PurchaseService` maps
//  RevenueCat offerings onto this; the paywall (task 6.2) renders it — so feature code
//  never imports the store SDK or its types. Prices come from the store at runtime
//  (locale-formatted), never hardcoded.
//

import Foundation

/// One purchasable Pro product, projected from a RevenueCat package. All three HeicSwap SKUs
/// unlock the same `pro` entitlement; `term` distinguishes how the user pays for it.
nonisolated struct PurchaseProduct: Identifiable, Sendable, Equatable, Hashable {

    /// Billing term, mapped from the offering's package type. Only the three terms HeicSwap
    /// sells are represented; any other package type is ignored when projecting an offering.
    enum Term: Sendable, Equatable, Hashable {
        case weekly
        case annual
        case lifetime
    }

    /// Store product identifier (matches App Store Connect / RevenueCat). Stable `id` for lists.
    let id: String
    /// How the user pays — drives ordering and the paywall's "best value" affordance (task 6.2).
    let term: Term
    /// Store-provided localized product name.
    let displayName: String
    /// Store-provided, locale-formatted price string (e.g. "$9.99") — display this verbatim.
    let localizedPrice: String
    /// Raw price for math (e.g. per-week equivalents, savings); display `localizedPrice` instead.
    let price: Decimal
}

/// The outcome of a purchase attempt. User cancellation is a normal flow, not an error, so it's
/// modeled here rather than thrown — callers switch on it instead of catching to detect dismissal.
nonisolated enum PurchaseOutcome: Sendable, Equatable {
    /// The purchase completed; `isPro` is the entitlement state the store reported afterwards.
    case purchased(isPro: Bool)
    /// The user dismissed the purchase sheet without buying.
    case userCancelled
}
