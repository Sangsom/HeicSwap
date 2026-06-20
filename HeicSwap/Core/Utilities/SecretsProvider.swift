//
//  SecretsProvider.swift
//  HeicSwap
//
//  Type-safe access to API keys and secrets injected at build time from .secrets.
//  Keys are parsed by the Generate Secrets build phase and passed via Info.plist.
//

import Foundation

enum SecretsProvider {

    /// RevenueCat API key for in-app purchases and subscriptions.
    /// Set in .secrets as REVENUECAT_API_KEY.
    static var revenueCatAPIKey: String? {
        Bundle.main.infoDictionary?["REVENUECAT_API_KEY"] as? String
    }
}
