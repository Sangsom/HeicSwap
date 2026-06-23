//
//  EntitlementStoreTests.swift
//  HeicSwapTests
//
//  The monetization store (task 6.1): products surface from the purchase client (AC1), a completed
//  purchase flips Pro on immediately (AC2), and a paid user is Pro at launch from the offline cache
//  and stays Pro when the refresh can't reach the store (AC3). The real RevenueCat offering→product
//  mapping and sandbox purchase/restore are exercised by the manual test plan; here the client is
//  mocked so the store's own logic (immediacy, caching, no-downgrade-offline) is verified in full.
//

import Foundation
import Testing
@testable import HeicSwap

// MARK: - Fixtures

/// A fresh, isolated `UserDefaults` suite per test so the cache never leaks between cases.
private func makeDefaults() -> UserDefaults {
    UserDefaults(suiteName: "EntitlementStoreTests-\(UUID().uuidString)")!
}

/// The three SKUs HeicSwap sells, shaped as the purchase client would return them.
private let sampleProducts = [
    PurchaseProduct(id: "pro.annual", term: .annual, displayName: "Pro Annual", localizedPrice: "$9.99", price: 9.99),
    PurchaseProduct(id: "pro.weekly", term: .weekly, displayName: "Pro Weekly", localizedPrice: "$1.99", price: 1.99),
    PurchaseProduct(id: "pro.lifetime", term: .lifetime, displayName: "Pro Lifetime", localizedPrice: "$19.99", price: 19.99),
]

/// A scriptable `PurchaseClient` standing in for RevenueCat. Each knob drives one branch of the
/// store under test; `entitlementCheckError` simulates being offline during a refresh.
@MainActor
private final class MockPurchaseClient: PurchaseClient {
    var products: [PurchaseProduct] = []
    var entitlementActive = false
    var purchaseOutcome: PurchaseOutcome = .purchased(isPro: true)
    var restoreIsPro = false
    var entitlementCheckError: Error?

    enum Failure: Error { case offline }

    func availableProducts() async throws -> [PurchaseProduct] { products }

    func purchase(_ product: PurchaseProduct) async throws -> PurchaseOutcome { purchaseOutcome }

    func restorePurchases() async throws -> Bool { restoreIsPro }

    func isProEntitlementActive() async throws -> Bool {
        if let entitlementCheckError { throw entitlementCheckError }
        return entitlementActive
    }
}

// MARK: - Tests

@MainActor
struct EntitlementStoreTests {

    @Test("AC1: fetched offerings surface the three products with their prices")
    func loadsThreeProductsWithPrices() async {
        let client = MockPurchaseClient()
        client.products = sampleProducts
        let store = EntitlementStore(purchaseClient: client, cache: EntitlementCache(defaults: makeDefaults()))

        await store.loadProducts()

        #expect(store.products.count == 3)
        #expect(store.products.map(\.localizedPrice) == ["$9.99", "$1.99", "$19.99"])
        #expect(Set(store.products.map(\.term)) == [.annual, .weekly, .lifetime])
    }

    @Test("AC2: a completed purchase flips isPro on immediately and caches it")
    func purchaseGrantsProImmediately() async throws {
        let defaults = makeDefaults()
        let client = MockPurchaseClient()
        client.purchaseOutcome = .purchased(isPro: true)
        let store = EntitlementStore(purchaseClient: client, cache: EntitlementCache(defaults: defaults))
        #expect(store.isPro == false)

        let outcome = try await store.purchase(sampleProducts[0])

        #expect(outcome == .purchased(isPro: true))
        #expect(store.isPro)
        #expect(store.entitlement == .pro)
        // Persisted, so the next launch is Pro before any network call.
        #expect(EntitlementCache(defaults: defaults).cachedEntitlement == .pro)
    }

    @Test("AC3: a paid user is Pro at launch from cache and stays Pro when the refresh fails offline")
    func offlineLaunchGrantsProFromCache() async {
        let defaults = makeDefaults()
        EntitlementCache(defaults: defaults).store(.pro) // a prior paid session

        let client = MockPurchaseClient()
        client.entitlementCheckError = MockPurchaseClient.Failure.offline // no connectivity
        let store = EntitlementStore(purchaseClient: client, cache: EntitlementCache(defaults: defaults))

        // Cached Pro is available synchronously from init, before any await.
        #expect(store.entitlement == .pro)

        await store.refresh() // the entitlement check throws internally
        #expect(store.entitlement == .pro) // not downgraded by the dropped call
    }

    @Test("Refresh reconciles with the store: an active entitlement grants Pro and caches it")
    func refreshGrantsAndCaches() async {
        let defaults = makeDefaults()
        let client = MockPurchaseClient()
        client.entitlementActive = true
        let store = EntitlementStore(purchaseClient: client, cache: EntitlementCache(defaults: defaults))
        #expect(store.isPro == false)

        await store.refresh()

        #expect(store.isPro)
        #expect(EntitlementCache(defaults: defaults).cachedEntitlement == .pro)
    }

    @Test("Refresh downgrades to free when the entitlement is no longer active and the store is reachable")
    func refreshDowngradesWhenInactive() async {
        let defaults = makeDefaults()
        EntitlementCache(defaults: defaults).store(.pro)
        let client = MockPurchaseClient()
        client.entitlementActive = false // expired / refunded, store reachable
        let store = EntitlementStore(purchaseClient: client, cache: EntitlementCache(defaults: defaults))
        #expect(store.entitlement == .pro) // seeded from cache

        await store.refresh()

        #expect(store.entitlement == .free) // reconciled down
        #expect(EntitlementCache(defaults: defaults).cachedEntitlement == .free)
    }

    @Test("A cancelled purchase leaves the entitlement untouched")
    func cancelledPurchaseKeepsEntitlement() async throws {
        let client = MockPurchaseClient()
        client.purchaseOutcome = .userCancelled
        let store = EntitlementStore(purchaseClient: client, cache: EntitlementCache(defaults: makeDefaults()))

        let outcome = try await store.purchase(sampleProducts[0])

        #expect(outcome == .userCancelled)
        #expect(store.isPro == false)
    }

    @Test("Restore applies the restored entitlement immediately")
    func restoreGrantsPro() async throws {
        let defaults = makeDefaults()
        let client = MockPurchaseClient()
        client.restoreIsPro = true
        let store = EntitlementStore(purchaseClient: client, cache: EntitlementCache(defaults: defaults))

        try await store.restore()

        #expect(store.isPro)
        #expect(EntitlementCache(defaults: defaults).cachedEntitlement == .pro)
    }

    @Suite("EntitlementCache")
    @MainActor
    struct EntitlementCacheTests {

        @Test("Defaults to free when nothing has been stored")
        func defaultsToFree() {
            #expect(EntitlementCache(defaults: makeDefaults()).cachedEntitlement == .free)
        }

        @Test("Round-trips the stored entitlement")
        func roundTrips() {
            let defaults = makeDefaults()
            let cache = EntitlementCache(defaults: defaults)

            cache.store(.pro)
            #expect(EntitlementCache(defaults: defaults).cachedEntitlement == .pro)

            cache.store(.free)
            #expect(EntitlementCache(defaults: defaults).cachedEntitlement == .free)
        }
    }
}
