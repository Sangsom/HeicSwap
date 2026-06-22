//
//  AnalyticsClient.swift
//  HeicSwap
//
//  The analytics boundary. Feature code depends on `AnalyticsClient` and the
//  type-safe `AnalyticsEvent` — never on a concrete analytics SDK. The production
//  conformer (`TelemetryDeckAnalyticsClient`) is the only file that imports the SDK.
//

import Foundation

// MARK: - Analytics Event

/// Type-safe analytics events. Maps to analytics event names and parameters.
/// The concrete event catalog is finalized in the analytics task (9.1); these are seeds.
enum AnalyticsEvent {
    case onboardingStarted
    case tabSelected(tab: String)
    case screenViewed(screen: String)
    /// A free user hit a value gate and was shown the paywall (task 6.3). `gate` is the
    /// `ValueGate.Trigger` raw value (`batch_size` / `target_size` / `strip_metadata`).
    case proGateHit(gate: String)
    case premiumPurchased(source: String)
    case premiumRestored

    var name: String {
        switch self {
        case .onboardingStarted: return "onboarding_started"
        case .tabSelected: return "tab_selected"
        case .screenViewed: return "screen_viewed"
        case .proGateHit: return "pro_gate_hit"
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
        case .proGateHit(let gate):
            return ["gate": gate]
        case .premiumPurchased(let source):
            return ["source": source]
        case .premiumRestored, .onboardingStarted:
            return nil
        }
    }
}

// MARK: - Analytics Client

/// Abstraction over the analytics SDK so feature code never imports it directly
/// (eases testing and the planned backend swap). Production conformer:
/// `TelemetryDeckAnalyticsClient`; tests and previews use `StubAnalyticsClient`.
protocol AnalyticsClient {
    /// Initializes the underlying analytics SDK. Call once, off the launch critical path.
    func configure()
    func logEvent(_ name: String, parameters: [String: Any]?)
}

extension AnalyticsClient {
    /// No-op by default so stub/test conformers need not implement it.
    func configure() {}

    func logEvent(_ name: String) {
        logEvent(name, parameters: nil)
    }

    func log(_ event: AnalyticsEvent) {
        logEvent(event.name, parameters: event.parameters)
    }
}

// MARK: - Stub Implementation

/// No-op analytics for previews, tests, and the `@Environment` default. Logs to the
/// console in DEBUG so events are visible without sending anything anywhere.
final class StubAnalyticsClient: AnalyticsClient {
    func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        #if DEBUG
        print("[Analytics] \(name) \(parameters ?? [:])")
        #endif
    }
}
