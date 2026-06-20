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
    var selectedTab: MainTab = .home

    let analyticsClient: any AnalyticsClient
    let purchaseService: PurchaseService

    /// Observes app foregrounding for the lifetime of the app. `AppState` is the
    /// root state object and is never torn down before process exit, so the task
    /// needs no explicit cancellation.
    private var foregroundObserverTask: Task<Void, Never>?

    init(analyticsClient: any AnalyticsClient, purchaseService: PurchaseService) {
        self.analyticsClient = analyticsClient
        self.purchaseService = purchaseService
        observeForeground()
    }

    /// Loads initial app state. Called from `.task` after the first frame, so SDK
    /// configuration stays off the launch critical path.
    func loadInitialState() {
        analyticsClient.configure()
        purchaseService.configure()
    }

    /// Refreshes state when app returns to foreground.
    func refreshOnForeground() {
        // Extend as needed: re-check subscription, sync data, etc.
    }

    private func observeForeground() {
        foregroundObserverTask = Task { [weak self] in
            let foregroundNotifications = NotificationCenter.default.notifications(
                named: UIApplication.willEnterForegroundNotification
            )
            for await _ in foregroundNotifications {
                self?.refreshOnForeground()
            }
        }
    }
}

enum MainTab: Int, CaseIterable {
    case home = 0
    case settings = 1
}
