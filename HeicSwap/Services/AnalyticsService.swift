//
//  AnalyticsService.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 23/02/2026.
//

import Foundation

// MARK: - Analytics Event

/// Type-safe analytics events. Maps to analytics event names and parameters.
enum AnalyticsEvent {
    case onboardingStarted
    case tabSelected(tab: String)
    case screenViewed(screen: String)
    case premiumPurchased(source: String)
    case premiumRestored

    var name: String {
        switch self {
        case .onboardingStarted: return "onboarding_started"
        case .tabSelected: return "tab_selected"
        case .screenViewed: return "screen_viewed"
        case .premiumPurchased: return "premium_purchased"
        case .premiumRestored: return "premium_restored"
        }
    }

    var parameters: [String: Any]? {
        switch self {
        case .tabSelected(let tab):
            return ["tab": tab]
        case .screenViewed(let screen):
            return ["screen": screen]
        case .premiumPurchased(let source):
            return ["source": source]
        case .premiumRestored, .onboardingStarted:
            return nil
        }
    }
}

// MARK: - Analytics Service Protocol

protocol AnalyticsService {
    func logEvent(_ name: String, parameters: [String: Any]?)
}

extension AnalyticsService {
    func logEvent(_ name: String) {
        logEvent(name, parameters: nil)
    }

    func log(_ event: AnalyticsEvent) {
        logEvent(event.name, parameters: event.parameters)
    }
}

// MARK: - Stub Implementation

final class StubAnalyticsService: AnalyticsService {
    func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        #if DEBUG
        print("[Analytics] \(name) \(parameters ?? [:])")
        #endif
    }
}
