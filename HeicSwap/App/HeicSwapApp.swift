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

    private let analyticsService: any AnalyticsService
    private let purchaseService: PurchaseService
    private let appState: AppState

    init() {
        analyticsService = StubAnalyticsService()
        purchaseService = PurchaseService()
        appState = AppState(analyticsService: analyticsService, purchaseService: purchaseService)
    }

    var body: some Scene {
        WindowGroup {
            MainTabView(appState: appState)
                .environment(\.analyticsService, analyticsService)
                .environment(\.purchaseService, purchaseService)
                .task {
                    appState.loadInitialState()
                }
        }
    }
}
