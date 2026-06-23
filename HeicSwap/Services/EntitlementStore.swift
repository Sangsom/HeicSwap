//
//  EntitlementStore.swift
//  HeicSwap
//
//  The single source of truth for what the user has unlocked. Wraps a `PurchaseClient`,
//  owns the observable `Entitlement`, and persists it so a paid user is Pro the instant the
//  app launches — even offline. Feature gating (task 6.3) and the paywall (task 6.2) read
//  this; neither touches `PurchaseClient` directly.
//

import Foundation

@Observable
@MainActor
final class EntitlementStore {

    /// What the user has unlocked. Seeded synchronously from the offline cache at init, then
    /// reconciled with the store by `refresh()`. Private setter — only this store mutates it.
    private(set) var entitlement: Entitlement

    /// Products available to purchase, loaded by `loadProducts()` for the paywall (task 6.2).
    private(set) var products: [PurchaseProduct] = []

    /// Convenience for gating checks (task 6.3).
    var isPro: Bool { entitlement.isPro }

    private let purchaseClient: any PurchaseClient
    private let cache: EntitlementCache

    init(purchaseClient: any PurchaseClient, cache: EntitlementCache = EntitlementCache()) {
        self.purchaseClient = purchaseClient
        self.cache = cache
        // Seed from the cache synchronously so a previously paid user holds Pro immediately on
        // launch, before any network call — and keeps it with no connectivity at all (AC3).
        self.entitlement = cache.cachedEntitlement
    }

    /// Reconciles the live entitlement with the store and caches the result. On failure (e.g.
    /// offline) the cached value is kept, so a paid user is never downgraded by a dropped network
    /// call (AC3). Safe to call on launch and on every foreground.
    func refresh() async {
        do {
            let isActive = try await purchaseClient.isProEntitlementActive()
            update(to: isActive ? .pro : .free)
        } catch {
            // Transient / offline — trust the cached entitlement rather than revoking Pro.
        }
    }

    /// Loads the purchasable products for the paywall (task 6.2). Leaves the previous list in
    /// place on failure so a transient fetch error doesn't blank an open paywall.
    func loadProducts() async {
        guard let fetched = try? await purchaseClient.availableProducts() else { return }
        products = fetched
    }

    /// Buys `product` and applies the resulting entitlement immediately on success, so Pro turns
    /// on the moment the purchase completes (AC2). Returns the outcome (including `.userCancelled`)
    /// for the caller to react to; rethrows a genuine purchase failure.
    @discardableResult
    func purchase(_ product: PurchaseProduct) async throws -> PurchaseOutcome {
        let outcome = try await purchaseClient.purchase(product)
        if case let .purchased(isPro) = outcome {
            update(to: isPro ? .pro : .free)
        }
        return outcome
    }

    /// Restores prior purchases and applies the resulting entitlement immediately.
    func restore() async throws {
        let isPro = try await purchaseClient.restorePurchases()
        update(to: isPro ? .pro : .free)
    }

    /// Updates the in-memory entitlement and mirrors it to the offline cache in one place.
    private func update(to entitlement: Entitlement) {
        self.entitlement = entitlement
        cache.store(entitlement)
    }
}

/// Persists the last-known entitlement for instant, offline-safe launches (AC3). Entitlement is
/// not a secret — it's a convenience mirror of the store's own server-validated state — so plain
/// `UserDefaults` is the right home: synchronous and ready before the first frame, no keychain
/// ceremony. The store remains authoritative; this only bridges the gap until `refresh()` lands.
struct EntitlementCache {

    private let defaults: UserDefaults
    private let key = "com.heicswap.entitlement.isPro"

    /// Inject a scoped suite in tests; defaults to `.standard` in the app.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The cached entitlement, or `.free` when nothing has been stored yet.
    var cachedEntitlement: Entitlement {
        defaults.bool(forKey: key) ? .pro : .free
    }

    /// Mirrors `entitlement` to disk for the next launch.
    func store(_ entitlement: Entitlement) {
        defaults.set(entitlement.isPro, forKey: key)
    }
}
