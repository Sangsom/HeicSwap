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

    /// On-device MetricKit crash/diagnostics capture (task 9.1). Retained for the app's lifetime so
    /// the subscription stays live; it sends nothing off-device.
    private let metricKitReporter = MetricKitReporter()

    /// `UserDefaults` flag recording that the app has launched at least once, so `app_launched` can
    /// report `is_first_launch` accurately (PRD §7) without relying on the onboarding flag.
    private static let hasLaunchedKey = "com.heicswap.analytics.hasLaunched"

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
        // Reclaim any temp files a previous (possibly killed) session left behind. Detached and off
        // the main actor so it never touches the launch critical path (task 10.3); this runs after
        // the first frame and the queue is always empty this early in a fresh process, so wiping the
        // whole workspace is safe.
        Task.detached(priority: .utility) { TempWorkspace.purgeAll() }

        analyticsClient.configure()
        analyticsClient.log(.appLaunched(isFirstLaunch: consumeIsFirstLaunch()))
        metricKitReporter.start()
        purchaseService.configure()
        await entitlementStore.refresh()
    }

    /// Whether this is the first launch since install, flipping the persisted flag so every later
    /// launch reports `false`. Reads/writes `UserDefaults` synchronously — cheap and off the
    /// critical path here.
    private func consumeIsFirstLaunch() -> Bool {
        let defaults = UserDefaults.standard
        let hasLaunched = defaults.bool(forKey: Self.hasLaunchedKey)
        if !hasLaunched { defaults.set(true, forKey: Self.hasLaunchedKey) }
        return !hasLaunched
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
