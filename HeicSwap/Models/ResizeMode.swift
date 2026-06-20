//
//  ResizeMode.swift
//  HeicSwap
//
//  How (or whether) a conversion resizes its output. The actual downscale and
//  target-size search are implemented by the engine (tasks 3.1–3.2); this type only
//  describes the user's intent.
//

import Foundation

/// Describes whether and how output images are resized.
///
/// `nonisolated` so it can cross the engine / UI actor boundary under default `@MainActor`
/// isolation. Because it carries associated values, `Sendable` / `Equatable` / `Hashable`
/// are declared explicitly rather than synthesized from `CaseIterable`.
nonisolated enum ResizeMode: Sendable, Equatable, Hashable {
    /// Keep the original pixel dimensions.
    case none
    /// Scale so the longest edge is at most this many pixels (aspect ratio preserved).
    case maxDimension(pixels: Int)
    /// Re-encode to land at or under this many bytes (quality search; an advanced feature).
    case targetBytes(Int)
}
