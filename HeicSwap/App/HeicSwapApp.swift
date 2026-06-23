//
//  HeicSwapApp.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 23/02/2026.
//

import SwiftUI

@main
struct HeicSwapApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let analyticsClient: any AnalyticsClient
    private let purchaseService: PurchaseService
    private let appState: AppState
    private let convertViewModel: ConvertViewModel

    init() {
        analyticsClient = TelemetryDeckAnalyticsClient()
        purchaseService = PurchaseService()
        appState = AppState(analyticsClient: analyticsClient, purchaseService: purchaseService)
        // Built once so the value-gate hits emit through the real analytics client (task 6.3);
        // its entitlement is synced from the store by the view. Seeded with the persisted conversion
        // defaults (task 8.1) so a fresh batch opens with the user's preferred format/quality/strip.
        convertViewModel = ConvertViewModel(
            analytics: analyticsClient,
            options: appState.conversionDefaults.seedOptions
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(convertViewModel: convertViewModel)
                .environment(appState)
                .environment(\.analyticsClient, analyticsClient)
                .environment(\.purchaseService, purchaseService)
                .environment(\.entitlementStore, appState.entitlementStore)
                .environment(\.conversionDefaults, appState.conversionDefaults)
                .task {
                    await appState.loadInitialState()
                }
        }
    }
}
