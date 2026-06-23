//
//  ResultsSummary.swift
//  HeicSwap
//
//  The totals shown atop the Results sheet (task 5.4): how many files were produced, their total
//  size, and how much space the run saved. Pure and total so it's unit-testable and can't drift
//  from what the sheet displays.
//

import Foundation

/// Builds the human-readable totals for a set of `ConversionResult`s.
///
/// `nonisolated` (the project defaults types to `@MainActor`) so the math and formatting are pure
/// and callable from tests. Byte sizes are rendered with `ByteCountFormatter` (`.file` style) for
/// the familiar "1.2 MB" look.
nonisolated enum ResultsSummary {

    /// Total input bytes across all outputs (sum of each result's `originalBytes`).
    static func totalOriginalBytes(_ results: [ConversionResult]) -> Int {
        results.reduce(0) { $0 + $1.originalBytes }
    }

    /// Total output bytes across all outputs.
    static func totalOutputBytes(_ results: [ConversionResult]) -> Int {
        results.reduce(0) { $0 + $1.outputBytes }
    }

    /// Bytes saved across the whole run; `0` when the outputs are collectively no smaller than the
    /// inputs (so the summary never claims negative savings).
    static func totalSaved(_ results: [ConversionResult]) -> Int {
        max(0, totalOriginalBytes(results) - totalOutputBytes(results))
    }

    /// Fraction of the original size that was saved, in `0.0...1.0`. `0` when there was nothing to
    /// measure or the run didn't shrink anything.
    static func savedFraction(_ results: [ConversionResult]) -> Double {
        let original = totalOriginalBytes(results)
        guard original > 0 else { return 0 }
        return Double(totalSaved(results)) / Double(original)
    }

    /// A byte size as a localized file-size string, e.g. `1_258_291` → "1.2 MB".
    static func sizeText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, bytes)), countStyle: .file)
    }

    /// "Saved 4.2 MB (62%)" when the run shrank the batch, otherwise `nil` (e.g. a PNG re-encode
    /// that grew, or a single faithful copy). The percentage is omitted below 1% to avoid a
    /// misleading "0%".
    static func savingsText(for results: [ConversionResult]) -> String? {
        let saved = totalSaved(results)
        guard saved > 0 else { return nil }

        let percent = Int((savedFraction(results) * 100).rounded())
        guard percent >= 1 else {
            return String(localized: "Saved \(sizeText(saved))")
        }
        return String(localized: "Saved \(sizeText(saved)) (\(percent)%)")
    }
}
