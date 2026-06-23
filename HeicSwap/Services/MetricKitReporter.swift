//
//  MetricKitReporter.swift
//  HeicSwap
//
//  On-device crash & performance diagnostics via MetricKit (task 9.1).
//

import Foundation
import MetricKit

/// Subscribes to `MXMetricManager` and persists each delivered payload to an on-device
/// `Diagnostics` directory.
///
/// **Nothing is ever sent off the device.** MetricKit payloads can carry stack traces and
/// call-site paths, so they stay local — honoring HeicSwap's privacy promise (AC3). Capturing
/// them on-device is enough to inspect a crash from a device on hand; dashboards are explicitly
/// out of scope. No image content, file names, or PII pass through here.
///
/// `nonisolated` because MetricKit invokes the subscriber callbacks on a background queue; the
/// class holds only an immutable directory URL, so it's safe to be driven off the main actor.
nonisolated final class MetricKitReporter: NSObject, MXMetricManagerSubscriber {

    private let directory: URL

    /// `directory` defaults to `Application Support/Diagnostics`, created on demand.
    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
        super.init()
    }

    /// Begins receiving MetricKit payloads. Call once, off the launch critical path.
    func start() {
        MXMetricManager.shared.add(self)
    }

    /// Stops receiving payloads. Symmetric with `start()`; not needed during the app's lifetime.
    func stop() {
        MXMetricManager.shared.remove(self)
    }

    // MARK: - MXMetricManagerSubscriber

    /// Daily performance metrics (launch time, hangs, memory, …). Persisted on-device only.
    func didReceive(_ payloads: [MXMetricPayload]) {
        persist(payloads.map { $0.jsonRepresentation() }, kind: "metrics")
    }

    /// Diagnostics including crashes, hangs, and disk-write exceptions. Persisted on-device only.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        persist(payloads.map { $0.jsonRepresentation() }, kind: "diagnostics")
    }

    // MARK: - Persistence

    /// Writes each payload's JSON to its own file in the on-device diagnostics directory. The
    /// payload bytes never leave the device — only an opaque count is printed in DEBUG.
    private func persist(_ payloads: [Data], kind: String) {
        guard !payloads.isEmpty else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for data in payloads {
            let url = directory.appending(path: "\(kind)-\(UUID().uuidString).json")
            try? data.write(to: url)
        }
        #if DEBUG
        print("[MetricKit] captured \(payloads.count) \(kind) payload(s) on-device")
        #endif
    }

    private static func defaultDirectory() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return base.appending(path: "Diagnostics", directoryHint: .isDirectory)
    }
}
