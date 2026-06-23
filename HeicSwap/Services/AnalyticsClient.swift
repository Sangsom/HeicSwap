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

/// The finalized analytics event catalog (task 9.1), mapping 1:1 to PRD §7. Each case names a
/// product moment and carries only **non-PII** parameters — counts, formats, durations, and
/// enumerated kinds. No image bytes, file names, or content ever travel through here.
///
/// Funnels these power: Activation (`appLaunched` → `imagesImported` → `conversionCompleted`) and
/// Monetization (`proGateHit` → `paywallShown` → `purchaseCompleted`).
///
/// `nonisolated` (like the model/policy enums) so events can be constructed and logged from any
/// isolation — the mapping is pure value logic with no actor state.
nonisolated enum AnalyticsEvent {
    /// App opened. `isFirstLaunch` is true only the very first launch after install (PRD §7).
    case appLaunched(isFirstLaunch: Bool)
    /// First-run onboarding appeared — start of the activation funnel (kept from task 7.1).
    case onboardingStarted
    /// Onboarding finished or was skipped. `screensViewed` is how many of the screens the user
    /// actually saw; `skipped` distinguishes the Skip button from completing the last screen.
    case onboardingCompleted(screensViewed: Int, skipped: Bool)
    /// Images were added to the queue. `source` is where they came from.
    case imagesImported(count: Int, source: ImportSource)
    /// Photo originals were fetched (downloaded from iCloud if optimized-away) on import.
    case icloudDownload(count: Int)
    /// A batch finished converting. Counts / formats / duration only (AC2) — never any content.
    case conversionCompleted(
        countSuccess: Int,
        countFailed: Int,
        targetFormat: String,
        isBatch: Bool,
        usedResize: Bool,
        usedStrip: Bool,
        toPDF: Bool,
        durationMs: Int
    )
    /// A free user hit a value gate and was shown the paywall (task 6.3). `gate` is the
    /// `ValueGate.Trigger` raw value (`batch_size` / `target_size` / `strip_metadata`).
    case proGateHit(gate: String)
    /// The paywall was presented. `trigger` is the gate that opened it, or `settings` for the
    /// permanent Settings entry.
    case paywallShown(trigger: String)
    /// A purchase completed. `productID` is the billing term (`annual` / `weekly` / `lifetime`).
    case purchaseCompleted(productID: String)
    /// An output was saved or shared. `destination` is where it went.
    case outputSaved(destination: SaveDestination)

    /// Where imported images came from.
    enum ImportSource: String {
        case photos
        case files
    }

    /// Where a finished output was sent.
    enum SaveDestination: String {
        case photos
        case files
        case share
    }

    var name: String {
        switch self {
        case .appLaunched: return "app_launched"
        case .onboardingStarted: return "onboarding_started"
        case .onboardingCompleted: return "onboarding_completed"
        case .imagesImported: return "images_imported"
        case .icloudDownload: return "icloud_download"
        case .conversionCompleted: return "conversion_completed"
        case .proGateHit: return "pro_gate_hit"
        case .paywallShown: return "paywall_shown"
        case .purchaseCompleted: return "purchase_completed"
        case .outputSaved: return "output_saved"
        }
    }

    var parameters: [String: Any]? {
        switch self {
        case let .appLaunched(isFirstLaunch):
            return ["is_first_launch": isFirstLaunch]
        case let .onboardingCompleted(screensViewed, skipped):
            return ["screens_viewed": screensViewed, "skipped": skipped]
        case let .imagesImported(count, source):
            return ["count": count, "source": source.rawValue]
        case let .icloudDownload(count):
            return ["count": count]
        case let .conversionCompleted(
            countSuccess, countFailed, targetFormat, isBatch, usedResize, usedStrip, toPDF, durationMs
        ):
            return [
                "count_success": countSuccess,
                "count_failed": countFailed,
                "target_format": targetFormat,
                "is_batch": isBatch,
                "used_resize": usedResize,
                "used_strip": usedStrip,
                "to_pdf": toPDF,
                "duration_ms": durationMs,
            ]
        case let .proGateHit(gate):
            return ["gate": gate]
        case let .paywallShown(trigger):
            return ["trigger": trigger]
        case let .purchaseCompleted(productID):
            return ["product_id": productID]
        case let .outputSaved(destination):
            return ["destination": destination.rawValue]
        case .onboardingStarted:
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
