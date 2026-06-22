//
//  PurchaseService.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 23/02/2026.
//
//  The only file that imports RevenueCat. RevenueCat-backed `PurchaseClient`; feature code
//  depends on the protocol and app-domain types, never the SDK. Offering → `PurchaseProduct`
//  mapping lives here so the SDK stays sealed behind this boundary.
//
//  Dashboard setup (App Store Connect + RevenueCat — sandbox now, live in task 11.1):
//    • Entitlement: "HeicSwap Pro" — granted by all three products. This is the entitlement
//      *identifier* as configured in the RevenueCat dashboard (verified against
//      /v1/product_entitlement_mapping); `entitlementIdentifier` below must match it exactly,
//      since `customerInfo.entitlements` is keyed by identifier. (If the dashboard entitlement is
//      ever renamed to a cleaner id like "pro", update the default below to match.)
//    • Offering "default" (current) with three packages:
//        – Annual   ($9.99/yr)   → package type Annual
//        – Weekly   ($1.99/wk)   → package type Weekly
//        – Lifetime ($19.99)     → package type Lifetime
//  Prices are read from the store at runtime, never hardcoded here.
//

import Foundation
import RevenueCat

@Observable
@MainActor
final class PurchaseService: PurchaseClient {

    private let entitlementIdentifier: String

    /// RevenueCat packages from the most recent `availableProducts()` fetch, keyed by product id,
    /// so `purchase(_:)` can recover the SDK package for an app-domain `PurchaseProduct`.
    private var packagesByProductID: [String: Package] = [:]

    init(entitlementIdentifier: String = "HeicSwap Pro") {
        self.entitlementIdentifier = entitlementIdentifier
    }

    /// Configures RevenueCat. No-op without an API key so it never blocks or crashes
    /// launch. Call once, off the launch critical path.
    func configure() {
        guard let apiKey = SecretsProvider.revenueCatAPIKey, !apiKey.isEmpty else {
            #if DEBUG
            print("⚠️ [Purchases] No REVENUECAT_API_KEY — staying on the free tier. Set it in .secrets and clean-build.")
            #endif
            return
        }
        #if DEBUG
        Purchases.logLevel = .verbose
        #endif
        Purchases.configure(withAPIKey: apiKey)
        #if DEBUG
        print("✅ [Purchases] Configured RevenueCat (key prefix \(apiKey.prefix(8))…).")
        #endif
    }

    /// Projects the current offering's packages into app-domain products, caching the underlying
    /// packages for `purchase(_:)`. Packages whose type isn't one HeicSwap sells are dropped.
    func availableProducts() async throws -> [PurchaseProduct] {
        guard Purchases.isConfigured else { throw PurchaseServiceError.notConfigured }
        let offerings = try await Purchases.shared.offerings()
        guard let current = offerings.current else {
            packagesByProductID = [:]
            return []
        }

        var products: [PurchaseProduct] = []
        var packages: [String: Package] = [:]
        for package in current.availablePackages {
            guard let product = Self.makeProduct(from: package) else { continue }
            products.append(product)
            packages[product.id] = package
        }
        packagesByProductID = packages
        return products
    }

    /// Buys the package behind `product`. Maps RevenueCat's result tuple to a `PurchaseOutcome`,
    /// reading the entitlement straight from the returned customer info so callers can update Pro
    /// state without a second round trip.
    func purchase(_ product: PurchaseProduct) async throws -> PurchaseOutcome {
        guard Purchases.isConfigured else { throw PurchaseServiceError.notConfigured }
        guard let package = packagesByProductID[product.id] else {
            throw PurchaseServiceError.productUnavailable
        }
        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled { return .userCancelled }
        return .purchased(isPro: isPro(in: result.customerInfo))
    }

    /// Restores previous purchases and reports whether Pro is now active.
    func restorePurchases() async throws -> Bool {
        guard Purchases.isConfigured else { throw PurchaseServiceError.notConfigured }
        let customerInfo = try await Purchases.shared.restorePurchases()
        return isPro(in: customerInfo)
    }

    /// Returns whether the Pro entitlement is currently active. Offline, RevenueCat returns its
    /// cached customer info, so this still answers truthfully for a previously paid user.
    func isProEntitlementActive() async throws -> Bool {
        guard Purchases.isConfigured else { throw PurchaseServiceError.notConfigured }
        let customerInfo = try await Purchases.shared.customerInfo()
        return isPro(in: customerInfo)
    }

    // MARK: - SDK mapping

    private func isPro(in customerInfo: CustomerInfo) -> Bool {
        customerInfo.entitlements[entitlementIdentifier]?.isActive == true
    }

    /// Projects a RevenueCat package into an app-domain product, or `nil` if its package type
    /// isn't a term HeicSwap sells.
    private static func makeProduct(from package: Package) -> PurchaseProduct? {
        guard let term = PurchaseProduct.Term(packageType: package.packageType) else { return nil }
        let storeProduct = package.storeProduct
        return PurchaseProduct(
            id: storeProduct.productIdentifier,
            term: term,
            displayName: storeProduct.localizedTitle,
            localizedPrice: storeProduct.localizedPriceString,
            price: storeProduct.price
        )
    }
}

/// Failures originating in the purchase boundary (distinct from RevenueCat's own errors).
enum PurchaseServiceError: Error {
    /// `purchase(_:)` was called for a product not present in the last `availableProducts()` fetch.
    case productUnavailable
    /// The SDK isn't configured — no API key was provided, so `configure()` was a no-op. Accessing
    /// `Purchases.shared` would trap, so SDK calls throw this instead (the store keeps its cache).
    case notConfigured
}

private extension PurchaseProduct.Term {
    /// Maps a RevenueCat package type to a HeicSwap term, or `nil` for types we don't sell.
    init?(packageType: PackageType) {
        switch packageType {
        case .weekly: self = .weekly
        case .annual: self = .annual
        case .lifetime: self = .lifetime
        default: return nil
        }
    }
}
