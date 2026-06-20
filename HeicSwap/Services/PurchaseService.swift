//
//  PurchaseService.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 23/02/2026.
//

import Foundation
import RevenueCat

@Observable
@MainActor
final class PurchaseService {

    private let entitlementIdentifier: String

    init(entitlementIdentifier: String = "pro") {
        self.entitlementIdentifier = entitlementIdentifier
    }

    /// Configures RevenueCat. Call once at app launch.
    func configure() {
        guard let apiKey = SecretsProvider.revenueCatAPIKey, !apiKey.isEmpty else { return }
        Purchases.configure(withAPIKey: apiKey)
    }

    /// Fetches current customer info (subscription status).
    func checkSubscription() async throws -> CustomerInfo {
        try await Purchases.shared.customerInfo()
    }

    /// Fetches available offerings for the paywall.
    func fetchOfferings() async throws -> Offerings {
        try await Purchases.shared.offerings()
    }

    /// Restores previous purchases.
    func restorePurchases() async throws -> CustomerInfo {
        try await Purchases.shared.restorePurchases()
    }

    /// Returns whether the pro entitlement is currently active.
    func isProEntitlementActive() async throws -> Bool {
        let customerInfo = try await checkSubscription()
        return customerInfo.entitlements[entitlementIdentifier]?.isActive == true
    }
}
