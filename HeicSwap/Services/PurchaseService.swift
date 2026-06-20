//
//  PurchaseService.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 23/02/2026.
//
//  The only file that imports RevenueCat. RevenueCat-backed `PurchaseClient`;
//  feature code depends on the protocol, never the SDK. Offerings / paywall surface
//  is built in the monetization task (6.1).
//

import Foundation
import RevenueCat

@Observable
@MainActor
final class PurchaseService: PurchaseClient {

    private let entitlementIdentifier: String

    init(entitlementIdentifier: String = "pro") {
        self.entitlementIdentifier = entitlementIdentifier
    }

    /// Configures RevenueCat. No-op without an API key so it never blocks or crashes
    /// launch. Call once, off the launch critical path.
    func configure() {
        guard let apiKey = SecretsProvider.revenueCatAPIKey, !apiKey.isEmpty else { return }
        Purchases.configure(withAPIKey: apiKey)
    }

    /// Returns whether the pro entitlement is currently active.
    func isProEntitlementActive() async throws -> Bool {
        let customerInfo = try await Purchases.shared.customerInfo()
        return customerInfo.entitlements[entitlementIdentifier]?.isActive == true
    }

    /// Restores previous purchases. Re-query `isProEntitlementActive()` afterwards.
    func restorePurchases() async throws {
        _ = try await Purchases.shared.restorePurchases()
    }
}
