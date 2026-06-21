//
//  ResizeOption.swift
//  HeicSwap
//
//  The flat, pickable projection of `ResizeMode` used by the Options sheet (task 5.2). The model
//  type carries associated values (pixel cap / byte target), so it can't drive a segmented
//  `Picker` directly; this maps it down to the three user choices and back, while the sheet
//  remembers the actual pixel / byte values across switches.
//

import Foundation

/// The three resize choices the Options sheet offers.
///
/// `nonisolated` (the project defaults types to `@MainActor`) so the mapping is pure and
/// unit-testable from any context. The Pro gate mirrors `ValueGate`: only target file size gates;
/// `.maxDimension` downscaling stays free.
nonisolated enum ResizeOption: String, CaseIterable, Identifiable, Sendable {
    /// Keep the original dimensions (`ResizeMode.none`).
    case original
    /// Cap the longest edge (`ResizeMode.maxDimension`) — free.
    case maxDimension
    /// Re-encode to land at or under a target file size (`ResizeMode.targetBytes`) — Pro-gated.
    case targetSize

    var id: String { rawValue }

    /// The choice a given mode represents.
    init(_ mode: ResizeMode) {
        switch mode {
        case .none: self = .original
        case .maxDimension: self = .maxDimension
        case .targetBytes: self = .targetSize
        }
    }

    /// Whether this choice is gated behind Pro. Mirrors `ValueGate.requiresPro`: target file size
    /// requires Pro; `.original` and `.maxDimension` are free.
    var requiresPro: Bool { self == .targetSize }

    /// Short, user-facing label for the segmented control.
    var displayName: String {
        switch self {
        case .original: String(localized: "Original")
        case .maxDimension: String(localized: "Max size")
        case .targetSize: String(localized: "File size")
        }
    }

    /// Builds the concrete `ResizeMode` for this choice from the sheet's remembered values.
    func mode(pixels: Int, bytes: Int) -> ResizeMode {
        switch self {
        case .original: .none
        case .maxDimension: .maxDimension(pixels: pixels)
        case .targetSize: .targetBytes(bytes)
        }
    }

    /// Preset longest-edge pixel caps offered for `.maxDimension`.
    static let pixelPresets = [1024, 2048, 4096]
    /// Default pixel cap when first switching to `.maxDimension` (matches the PDF page cap).
    static let defaultPixels = 2048

    /// Preset target file sizes, in bytes, offered for `.targetSize`.
    static let bytePresets = [500_000, 1_000_000, 2_000_000]
    /// Default target size when first switching to `.targetSize`.
    static let defaultBytes = 1_000_000
}
