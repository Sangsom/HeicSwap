//
//  MainTabView.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 23/02/2026.
//

import SwiftUI

struct MainTabView: View {
    @Bindable private var appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            HomeScreen()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(MainTab.home)

            SettingsScreen()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(MainTab.settings)
        }
    }
}

#Preview {
    let appState = AppState(
        analyticsService: StubAnalyticsService(),
        purchaseService: PurchaseService()
    )
    return MainTabView(appState: appState)
}
