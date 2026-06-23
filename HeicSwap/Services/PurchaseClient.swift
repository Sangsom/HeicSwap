//
//  PurchaseClient.swift
//  HeicSwap
//
//  The in-app-purchase boundary. Feature code depends on `PurchaseClient` and never
//  imports RevenueCat directly (eases testing and the planned v1.1 swap). The surface
//  speaks app-domain types (`PurchaseProduct`, `PurchaseOutcome`, `Entitlement`), never
//  SDK types, to keep the boundary clean. Production conformer: `PurchaseService`;
//  tests and previews use `StubPurchaseClient`.
//

import Foundation

protocol PurchaseClient {
    /// Initializes the underlying purchase SDK. Call once, off the launch critical path.
    func configure()
    /// The Pro products available to buy, projected from the current offering. Empty if no
    /// offering is configured or none of its packages map to a HeicSwap term.
    func availableProducts() async throws -> [PurchaseProduct]
    /// Buys `product`. Returns the resulting entitlement state, or `.userCancelled` if the
    /// user dismissed the sheet. Throws on a genuine purchase failure.
    func purchase(_ product: PurchaseProduct) async throws -> PurchaseOutcome
    /// Restores previously purchased entitlements and returns whether Pro is now active.
    func restorePurchases() async throws -> Bool
    /// Whether the user currently holds the Pro entitlement.
    func isProEntitlementActive() async throws -> Bool
}

extension PurchaseClient {
    /// No-op by default so stub / test conformers need not implement SDK setup.
    func configure() {}
}

// MARK: - Stub Implementation

/// No-op purchase client for previews, tests, and the `@Environment` default. Reports the free
/// tier and offers no products — never touches the App Store. Tweak the stored values to preview
/// a Pro user or a populated paywall without a network or sandbox account.
final class StubPurchaseClient: PurchaseClient {
    var isPro: Bool
    var products: [PurchaseProduct]

    init(isPro: Bool = false, products: [PurchaseProduct] = []) {
        self.isPro = isPro
        self.products = products
    }

    func availableProducts() async throws -> [PurchaseProduct] { products }

    func purchase(_ product: PurchaseProduct) async throws -> PurchaseOutcome {
        .purchased(isPro: isPro)
    }

    func restorePurchases() async throws -> Bool { isPro }

    func isProEntitlementActive() async throws -> Bool { isPro }
}
