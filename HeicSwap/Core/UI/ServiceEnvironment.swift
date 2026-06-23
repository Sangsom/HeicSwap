//
//  ServiceEnvironment.swift
//  HeicSwap
//
//  Environment keys for injecting services into the view hierarchy.
//

import SwiftUI

// MARK: - Analytics Client

private struct AnalyticsClientKey: EnvironmentKey {
    static let defaultValue: any AnalyticsClient = StubAnalyticsClient()
}

extension EnvironmentValues {
    var analyticsClient: any AnalyticsClient {
        get { self[AnalyticsClientKey.self] }
        set { self[AnalyticsClientKey.self] = newValue }
    }
}

// MARK: - Purchase Service

private struct PurchaseServiceKey: EnvironmentKey {
    static let defaultValue: PurchaseService = PurchaseService()
}

extension EnvironmentValues {
    var purchaseService: PurchaseService {
        get { self[PurchaseServiceKey.self] }
        set { self[PurchaseServiceKey.self] = newValue }
    }
}

// MARK: - Entitlement Store

private struct EntitlementStoreKey: EnvironmentKey {
    /// Free-tier default backed by a no-op client, for previews and views rendered outside the app.
    static let defaultValue = EntitlementStore(purchaseClient: StubPurchaseClient())
}

extension EnvironmentValues {
    var entitlementStore: EntitlementStore {
        get { self[EntitlementStoreKey.self] }
        set { self[EntitlementStoreKey.self] = newValue }
    }
}

// MARK: - Conversion Defaults

private struct ConversionDefaultsKey: EnvironmentKey {
    /// A standalone defaults store for previews and views rendered outside the app.
    static let defaultValue = ConversionDefaults()
}

extension EnvironmentValues {
    var conversionDefaults: ConversionDefaults {
        get { self[ConversionDefaultsKey.self] }
        set { self[ConversionDefaultsKey.self] = newValue }
    }
}
