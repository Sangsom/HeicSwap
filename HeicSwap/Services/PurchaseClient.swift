//
//  PurchaseClient.swift
//  HeicSwap
//
//  The in-app-purchase boundary. Feature code depends on `PurchaseClient` and never
//  imports RevenueCat directly (eases testing and the planned v1.1 swap). The surface
//  grows in the monetization task (6.1) — adding offerings/purchase using app-domain
//  types, never SDK types, to keep the boundary clean.
//

import Foundation

protocol PurchaseClient {
    /// Initializes the underlying purchase SDK. Call once, off the launch critical path.
    func configure()
    /// Whether the user currently holds the pro entitlement.
    func isProEntitlementActive() async throws -> Bool
    /// Restores previously purchased entitlements. Re-query entitlement state afterwards.
    func restorePurchases() async throws
}
