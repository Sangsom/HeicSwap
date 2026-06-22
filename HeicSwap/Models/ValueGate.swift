//
//  ValueGate.swift
//  HeicSwap
//
//  The single source of truth for the monetization gate the whole funnel depends on
//  (PRD §6). A run is free when it stays within the free batch limit and uses only
//  free features; Pro is required past the limit or for the advanced features. This is
//  pure, stateless policy — no daily counter, no store knowledge. The paywall trigger
//  (task 6.3) and options UI locks (task 5.2) read this; the entitlement check (task 6.1)
//  decides what to do when it returns `true`.
//

import Foundation

/// The value-gate policy: does a given conversion run require Pro?
///
/// `nonisolated` so the engine (off the main actor) and the UI (main actor) can both call
/// it freely under the app's default `@MainActor` isolation. Implemented as a namespace
/// rather than a free function so `FREE_BATCH_LIMIT` and the rule that reads it live in one
/// place and can't drift apart.
nonisolated enum ValueGate {

    /// `FREE_BATCH_LIMIT` — the largest batch (conversion *or* image→PDF) the free tier
    /// allows. Centralized here as the single A/B knob: launch value is 5, with 3 / 8 the
    /// other candidates (PRD §7). Changing this one constant retunes the entire gate.
    static let freeBatchLimit = 5

    /// Which gate a run trips — so the paywall knows *why* it appeared and analytics can record
    /// the kind (`pro_gate_hit`, task 6.3). The raw value is the analytics parameter verbatim.
    /// `Identifiable` so it can drive a SwiftUI `.sheet(item:)` directly.
    enum Trigger: String, Sendable, Hashable, Identifiable, CaseIterable {
        /// The batch is larger than `freeBatchLimit` (conversion *or* image→PDF).
        case batchSize = "batch_size"
        /// Resizing targets a specific output file size (`ResizeMode.targetBytes`).
        case targetSize = "target_size"
        /// Metadata stripping is on.
        case stripMetadata = "strip_metadata"

        var id: String { rawValue }
    }

    /// Which Pro gate converting `items` with `options` trips, or `nil` when the run is free.
    ///
    /// The rule (PRD §6), in priority order:
    /// 1. the batch exceeds `freeBatchLimit` — applies to plain conversion *and* image→PDF,
    /// 2. metadata stripping is on, or
    /// 3. resizing targets a specific output file size (`ResizeMode.targetBytes`).
    ///
    /// Everything else is free: any output `format` (PDF included — small image→PDF is our
    /// top acquisition term and must never paywall on first use), and `.maxDimension`
    /// downscaling. Pure and total — it inspects only `items.count` and `options`. The order
    /// matters: a six-image run reports `.batchSize` even if it also strips (AC1, task 6.3).
    static func proTrigger(items: [SourceItem], options: ConversionOptions) -> Trigger? {
        if items.count > freeBatchLimit { return .batchSize }
        if options.stripsMetadata { return .stripMetadata }
        if case .targetBytes = options.resizeMode { return .targetSize }
        return nil
    }

    /// Whether converting `items` with `options` requires Pro — the boolean view of `proTrigger`,
    /// kept for the options-sheet locks (task 5.2) and callers that don't need the specific gate.
    static func requiresPro(items: [SourceItem], options: ConversionOptions) -> Bool {
        proTrigger(items: items, options: options) != nil
    }
}
