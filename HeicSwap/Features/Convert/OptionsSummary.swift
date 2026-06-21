//
//  OptionsSummary.swift
//  HeicSwap
//
//  The one-line summary of the current `ConversionOptions` shown on the Convert screen's options
//  row — the tap target that presents the sheet (task 5.2). Pure and total so it's unit-testable
//  and can't drift from the choices the sheet actually applies.
//

import Foundation

/// Builds compact, human-readable summaries of a `ConversionOptions` value.
///
/// `nonisolated` (the project defaults types to `@MainActor`) so the formatting is pure and
/// callable from tests. Fragments are dropped when they don't apply, so the summary stays short.
nonisolated enum OptionsSummary {

    /// A compact "JPEG · 90% · Max 2048px" style summary. Quality appears only for lossy formats,
    /// resize only when set, and "No metadata" only when stripping. Joined with " · ".
    static func text(for options: ConversionOptions) -> String {
        var parts: [String] = [options.format.displayName]

        if options.format.usesQuality {
            parts.append(qualityText(options.quality))
        }

        switch options.resizeMode {
        case .none:
            break
        case let .maxDimension(pixels):
            parts.append(String(localized: "Max \(pixelText(pixels))"))
        case let .targetBytes(bytes):
            parts.append(String(localized: "≤ \(byteText(bytes))"))
        }

        if options.stripsMetadata {
            parts.append(String(localized: "No metadata"))
        }

        return parts.joined(separator: " · ")
    }

    /// Quality as a whole percentage, e.g. `0.9` → "90%".
    static func qualityText(_ quality: Double) -> String {
        "\(Int((quality * 100).rounded()))%"
    }

    /// A longest-edge pixel cap as a label, e.g. `2048` → "2048 px". The count is interpolated as
    /// a plain string so it never picks up a locale grouping separator ("2 048").
    static func pixelText(_ pixels: Int) -> String {
        "\(pixels) px"
    }

    /// A target file size as a human label, e.g. `1_000_000` → "1 MB".
    static func byteText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
