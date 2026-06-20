//
//  TelemetryDeckAnalyticsClient.swift
//  HeicSwap
//
//  The only file that imports TelemetryDeck. Privacy-first analytics fronted by
//  `AnalyticsClient`. This wrapper owns SDK lifecycle and signal forwarding only —
//  the event catalog and MetricKit reporting are built in the analytics task (9.1).
//

import Foundation
import TelemetryDeck

/// `AnalyticsClient` backed by TelemetryDeck. No-ops entirely when no app ID is
/// configured (e.g. local builds), so analytics never blocks or crashes launch and
/// never sends content or PII.
final class TelemetryDeckAnalyticsClient: AnalyticsClient {

    private let appID: String?

    init(appID: String? = SecretsProvider.telemetryDeckAppID) {
        self.appID = appID
    }

    /// Initializes TelemetryDeck. Call once, off the launch critical path.
    func configure() {
        guard let appID, !appID.isEmpty else { return }
        let configuration = TelemetryDeck.Config(appID: appID)
        TelemetryDeck.initialize(config: configuration)
    }

    func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        guard let appID, !appID.isEmpty else { return }
        let stringParameters = parameters?.reduce(into: [String: String]()) { result, pair in
            result[pair.key] = String(describing: pair.value)
        } ?? [:]
        TelemetryDeck.signal(name, parameters: stringParameters)
    }
}
