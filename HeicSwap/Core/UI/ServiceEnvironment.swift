//
//  ServiceEnvironment.swift
//  HeicSwap
//
//  Environment keys for injecting services into the view hierarchy.
//

import SwiftUI

// MARK: - Analytics Service

private struct AnalyticsServiceKey: EnvironmentKey {
    static let defaultValue: any AnalyticsService = StubAnalyticsService()
}

extension EnvironmentValues {
    var analyticsService: any AnalyticsService {
        get { self[AnalyticsServiceKey.self] }
        set { self[AnalyticsServiceKey.self] = newValue }
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
