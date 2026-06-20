//
//  Layout.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 23/02/2026.
//

import CoreGraphics

extension Theme {

    /// Spacing scale on a 4pt grid (design spec §5). Use these instead of
    /// magic numbers so rhythm stays consistent across screens.
    enum Spacing {
        /// 4 — tight pairings (icon + label).
        static let tight: CGFloat = 4
        /// 8 — within a component.
        static let small: CGFloat = 8
        /// 12 — between list items.
        static let item: CGFloat = 12
        /// 16 — section padding.
        static let section: CGFloat = 16
        /// 24 — between sections.
        static let sectionGap: CGFloat = 24
        /// 32 — major breaks.
        static let majorBreak: CGFloat = 32
    }

    /// Corner radii — warm/filmic, slightly rounder (design spec §5).
    /// Badges use a capsule shape rather than a fixed radius.
    enum Radius {
        /// 14 — buttons.
        static let button: CGFloat = 14
        /// 18 — cards and sheets.
        static let card: CGFloat = 18
        /// 12 — inputs.
        static let input: CGFloat = 12
        /// 10 — thumbnails.
        static let thumbnail: CGFloat = 10
    }
}
