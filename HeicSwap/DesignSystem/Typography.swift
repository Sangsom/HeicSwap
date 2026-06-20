//
//  Typography.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 23/02/2026.
//

import SwiftUI

extension Theme {

    /// Warm Darkroom type scale (design spec §5).
    ///
    /// **Display titles use a serif** (the system New York face via
    /// `design: .serif`) for the photographic, darkroom personality; **everything
    /// else uses the system sans** (SF Pro) for legible UI and body copy. Serif is
    /// for display only — never body. Every style is built on a `Font.TextStyle`,
    /// so all of them scale with Dynamic Type.
    enum Typography {

        // MARK: Display — serif (New York)

        /// Screen titles, e.g. "Convert". 34 · Bold · serif.
        static let largeTitle = Font.serif(.largeTitle, weight: .bold)

        /// Section / prominent titles. Semibold · serif.
        static let title = Font.serif(.title, weight: .semibold)

        /// Paywall headline, empty-state line. 22 · Semibold · serif.
        static let title2 = Font.serif(.title2, weight: .semibold)

        // MARK: UI & body — system (SF Pro)

        /// List item titles, format labels. 17 · Semibold.
        static let headline = Font.headline

        /// Primary content. 17 · Regular.
        static let body = Font.body

        /// Secondary content. 16 · Regular.
        static let callout = Font.callout

        /// Settings rows, secondary content. 15 · Regular.
        static let subheadline = Font.subheadline

        /// "Free left today", hints. 13 · Regular.
        static let footnote = Font.footnote

        /// Badges, file sizes. 12 · Regular.
        static let caption = Font.caption
    }
}

extension Font {

    /// A Warm Darkroom serif display font built on a Dynamic-Type text style.
    ///
    /// Uses the system serif (New York), so it scales with the user's text-size
    /// setting and needs no bundled font files. Reserve this for display/titles;
    /// body and UI copy stay on the system sans.
    ///
    /// - Parameters:
    ///   - style: The text style to scale against (e.g. `.largeTitle`, `.title2`).
    ///   - weight: The font weight. Defaults to `.regular`.
    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
    }
}
