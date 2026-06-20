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

    /// Whether converting `items` with `options` requires Pro.
    ///
    /// The rule (PRD §6), in priority order:
    /// 1. the batch exceeds `freeBatchLimit` — applies to plain conversion *and* image→PDF,
    /// 2. metadata stripping is on, or
    /// 3. resizing targets a specific output file size (`ResizeMode.targetBytes`).
    ///
    /// Everything else is free: any output `format` (PDF included — small image→PDF is our
    /// top acquisition term and must never paywall on first use), and `.maxDimension`
    /// downscaling. Pure and total — it inspects only `items.count` and `options`.
    static func requiresPro(items: [SourceItem], options: ConversionOptions) -> Bool {
        if items.count > freeBatchLimit { return true }
        if options.stripsMetadata { return true }
        if case .targetBytes = options.resizeMode { return true }
        return false
    }
}
