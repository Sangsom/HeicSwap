//
//  Colors.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 23/02/2026.
//

import SwiftUI

extension Theme {

    /// Warm Darkroom color tokens.
    ///
    /// Every token resolves to an asset-catalog color with two appearances —
    /// **light = Warm Paper**, **dark = Darkroom** — so all of them adapt to the
    /// system (or in-app) appearance automatically. Hex values are the design
    /// spec §5 source of truth.
    ///
    /// Features must reference these tokens. Never hardcode a `Color(red:…)`,
    /// a hex literal, or a system color in feature code — add a token here instead.
    enum Colors {

        /// App background. Light `#FBF3EC` · Dark `#1A1413`.
        static let background = Color("Background")

        /// Cards and sheets. Light `#FFFDF9` · Dark `#251B18`.
        static let surface = Color("Surface")

        /// Inputs and chips — one step up from `surface`. Light `#F3E7DC` · Dark `#30221E`.
        static let surface2 = Color("Surface2")

        /// Headlines and body text. Light `#2A1F1A` · Dark `#F4EBE3`.
        static let textPrimary = Color("TextPrimary")

        /// Captions and hints. Light `#6E5D52` · Dark `#B6A398`.
        static let textSecondary = Color("TextSecondary")

        /// Safelight amber — CTA, active, glow. Light `#D9542F` · Dark `#FF7B54`.
        /// Mirrors the asset-catalog `AccentColor`, so the global SwiftUI tint matches.
        static let accent = Color("AccentColor")

        /// Gradient end / emphasis. `#E84B3C` in both appearances.
        static let accent2 = Color("Accent2")

        /// Foreground for content placed *on* the amber accent (buttons, badges).
        /// Always the dark ink `#23100B` — never white (white-on-amber fails AA).
        static let onAccent = Color("OnAccent")

        /// Done / success states. Light `#4E8A52` · Dark `#5FB07A`.
        static let success = Color("Success")

        /// Delete / remove. Light `#C8432F` · Dark `#FF6A52`.
        static let destructive = Color("Destructive")

        /// Hairline separators. Light `#EBDDD0` · Dark `#3A2A25`.
        /// (Asset named `Hairline` to avoid colliding with the system `UIColor.separator` symbol.)
        static let separator = Color("Hairline")
    }
}
