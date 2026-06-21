//
//  DevelopReveal.swift
//  HeicSwap
//
//  The signature "developing" reveal (task 5.3): as each queued thumbnail finishes converting it
//  emerges from dark to full color, like a photo surfacing in a darkroom tray. This type holds the
//  pure visual recipe — the brightness/saturation sweep, and the Reduce-Motion crossfade that
//  replaces it — so the branch behaviour is unit-testable and can't drift from what the cell draws.
//

import Foundation

/// Visual treatment for a queue thumbnail as it "develops" during a batch conversion.
///
/// `nonisolated` (the project defaults types to `@MainActor`) so the recipe is pure and callable
/// from tests. The cell animates *between* the undeveloped and developed styles when its item
/// finishes; the styles themselves carry no animation.
nonisolated enum DevelopReveal {

    /// The three animatable axes the cell applies to its thumbnail.
    ///
    /// Two are mutually exclusive by design: the develop sweep moves `brightness` / `saturation`
    /// with `opacity` held at full, while the Reduce-Motion crossfade moves only `opacity` with the
    /// other two held at their developed values. Keeping them on separate axes is what makes the
    /// fallback a true crossfade rather than a dimmed sweep (AC2).
    struct Style: Equatable {
        /// Additive brightness for SwiftUI's `.brightness` (`0` = unchanged, negative = darker).
        var brightness: Double
        /// Saturation multiplier for `.saturation` (`1` = full color).
        var saturation: Double
        /// Opacity for `.opacity` (`1` = fully shown).
        var opacity: Double
    }

    /// A fully developed thumbnail: true color, full brightness, fully shown. The shared end state
    /// of both the sweep and the crossfade — and the resting state whenever no conversion is running.
    static let developed = Style(brightness: 0, saturation: 1, opacity: 1)

    /// Duration of the develop transition, in seconds. Long enough to read as a deliberate
    /// "developing" beat; short enough to keep a batch feeling responsive.
    static let duration: Double = 0.55

    /// The style a thumbnail should currently render with.
    ///
    /// - `isDeveloped` is `true` once the item has finished converting (and whenever no conversion
    ///   is in flight), giving `developed`.
    /// - While undeveloped, motion users get the dark, desaturated "in the developer" look that
    ///   then sweeps up to full color; Reduce-Motion users instead get a dimmed thumbnail that
    ///   simply crossfades in — no brightness/saturation motion at all.
    static func style(isDeveloped: Bool, reduceMotion: Bool) -> Style {
        guard !isDeveloped else { return developed }
        return reduceMotion
            ? Style(brightness: developed.brightness, saturation: developed.saturation, opacity: 0.3)
            : Style(brightness: -0.5, saturation: 0.4, opacity: developed.opacity)
    }
}
