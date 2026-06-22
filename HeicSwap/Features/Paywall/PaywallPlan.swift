//
//  PaywallPlan.swift
//  HeicSwap
//
//  The pure presentation logic behind the paywall (task 6.2): how the purchasable products map to
//  named, priced, ordered rows and which one is highlighted by default. Kept SwiftUI-free so the
//  ordering and the "annual is the default highlight" rule (AC1) are unit-tested without rendering.
//

import Foundation

/// One purchasable product projected for a paywall row: a plain-language title, a per-term price
/// line, and whether it's the honest best value (the annual plan, which is also the default
/// selection — AC1). Prices come verbatim from the store via `PurchaseProduct`, never hardcoded.
///
/// `nonisolated` (the project defaults types to `@MainActor`) so the projection is pure and
/// testable from any context, like `OptionsSummary` / `ResizeOption`.
nonisolated struct PaywallPlan: Identifiable, Equatable {

    let product: PurchaseProduct

    var id: String { product.id }

    init(_ product: PurchaseProduct) {
        self.product = product
    }

    /// Plan name shown on the row: "Yearly" / "Weekly" / "Lifetime".
    var title: String {
        switch product.term {
        case .annual: return String(localized: "Yearly")
        case .weekly: return String(localized: "Weekly")
        case .lifetime: return String(localized: "Lifetime")
        }
    }

    /// Price line beneath the title, built from the store's localized price string plus an honest
    /// billing-period suffix — e.g. "$9.99 / year", "$1.99 / week", "$19.99 one-time".
    var priceDetail: String {
        switch product.term {
        case .annual: return String(localized: "\(product.localizedPrice) / year")
        case .weekly: return String(localized: "\(product.localizedPrice) / week")
        case .lifetime: return String(localized: "\(product.localizedPrice) one-time")
        }
    }

    /// The annual plan is the genuine best value — the lowest effective rate and the default
    /// highlight. No countdown, no pre-selected weekly (task 6.2's honesty bar).
    var isBestValue: Bool { product.term == .annual }

    /// Stable display order: annual first (the default), then weekly, then lifetime.
    fileprivate var sortRank: Int {
        switch product.term {
        case .annual: return 0
        case .weekly: return 1
        case .lifetime: return 2
        }
    }
}

extension PaywallPlan {

    /// Projects the store's products into ordered paywall rows: annual, weekly, lifetime.
    static func plans(from products: [PurchaseProduct]) -> [PaywallPlan] {
        products.map(PaywallPlan.init).sorted { $0.sortRank < $1.sortRank }
    }

    /// The product id to highlight when the paywall opens: the annual plan if offered, otherwise the
    /// first listed plan (AC1: annual is default-highlighted). `nil` only when no products loaded.
    static func defaultSelectionID(in products: [PurchaseProduct]) -> String? {
        let ordered = plans(from: products)
        return (ordered.first(where: \.isBestValue) ?? ordered.first)?.id
    }
}
