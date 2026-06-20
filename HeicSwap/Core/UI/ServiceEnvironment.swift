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
