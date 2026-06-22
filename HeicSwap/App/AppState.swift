//
//  AppState.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 23/02/2026.
//

import Foundation
import SwiftUI

@Observable
@MainActor
final class AppState {
    let analyticsClient: any AnalyticsClient
    let purchaseService: PurchaseService
    /// The app-wide entitlement source of truth (task 6.1), backed by `purchaseService` and an
    /// offline cache. Reads Pro state instantly at launch; `refresh()` reconciles with the store.
    let entitlementStore: EntitlementStore
    /// The user's persisted conversion defaults (task 8.1), edited in Settings and used to seed the
    /// Convert screen's session options.
    let conversionDefaults: ConversionDefaults

    /// Observes app foregrounding for the lifetime of the app. `AppState` is the
    /// root state object and is never torn down before process exit, so the task
    /// needs no explicit cancellation.
    private var foregroundObserverTask: Task<Void, Never>?

    init(
        analyticsClient: any AnalyticsClient,
        purchaseService: PurchaseService,
        conversionDefaults: ConversionDefaults = ConversionDefaults()
    ) {
        self.analyticsClient = analyticsClient
        self.purchaseService = purchaseService
        self.entitlementStore = EntitlementStore(purchaseClient: purchaseService)
        self.conversionDefaults = conversionDefaults
        observeForeground()
    }

    /// Loads initial app state. Called from `.task` after the first frame, so SDK
    /// configuration stays off the launch critical path. The entitlement refresh runs after the
    /// SDKs are configured; the store already reflects the cached entitlement from its init (AC3).
    func loadInitialState() async {
        analyticsClient.configure()
        purchaseService.configure()
        await entitlementStore.refresh()
    }

    /// Refreshes state when app returns to foreground — re-checks the entitlement so a renewal or
    /// expiry that happened off-app is reflected.
    func refreshOnForeground() async {
        await entitlementStore.refresh()
    }

    private func observeForeground() {
        foregroundObserverTask = Task { [weak self] in
            let foregroundNotifications = NotificationCenter.default.notifications(
                named: UIApplication.willEnterForegroundNotification
            )
            for await _ in foregroundNotifications {
                await self?.refreshOnForeground()
            }
        }
    }
}

enum MainTab: Int, CaseIterable {
    case home = 0
    case settings = 1
}
