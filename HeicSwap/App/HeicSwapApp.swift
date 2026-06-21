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

    init() {
        analyticsClient = TelemetryDeckAnalyticsClient()
        purchaseService = PurchaseService()
        appState = AppState(analyticsClient: analyticsClient, purchaseService: purchaseService)
    }

    var body: some Scene {
        WindowGroup {
            ConvertView()
                .environment(appState)
                .environment(\.analyticsClient, analyticsClient)
                .environment(\.purchaseService, purchaseService)
                .task {
                    appState.loadInitialState()
                }
        }
    }
}
