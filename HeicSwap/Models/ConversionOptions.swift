//
//  ConversionOptions.swift
//  HeicSwap
//
//  The full set of choices for one conversion run, shared by the options sheet (task 5.2)
//  and the conversion engine (task 3.1). A plain value type: it describes intent and holds
//  no behavior.
//

import Foundation

/// User-selected settings for a conversion: target format, quality, resizing, and whether
/// to strip metadata.
///
/// `nonisolated` so the engine (off the main actor) and the options UI (main actor) share
/// the same instance. Defaults match the free-tier happy path (JPEG, high quality, no
/// resize, metadata kept); gating of advanced choices is applied separately in task 2.2.
nonisolated struct ConversionOptions: Sendable, Equatable, Hashable {
    /// Target output format.
    var format: OutputFormat
    /// Compression quality in `0.0...1.0`. Applies only when `format.usesQuality` is true.
    var quality: Double
    /// Whether and how to resize the output.
    var resizeMode: ResizeMode
    /// Strip EXIF / GPS and other metadata from the output (privacy feature, task 3.3).
    var stripsMetadata: Bool

    init(
        format: OutputFormat = .jpg,
        quality: Double = 0.9,
        resizeMode: ResizeMode = .none,
        stripsMetadata: Bool = false
    ) {
        self.format = format
        self.quality = quality
        self.resizeMode = resizeMode
        self.stripsMetadata = stripsMetadata
    }
}
