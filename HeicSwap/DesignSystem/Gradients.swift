//
//  Gradients.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 23/02/2026.
//

import SwiftUI

extension Theme {

    /// Warm Darkroom gradients (design spec §5).
    enum Gradients {

        /// The safelight amber wash — `accent` → `accent2` — that sits behind the
        /// queue and on glow surfaces. Both stops are appearance-adaptive, so the
        /// glow warms correctly in Darkroom (dark) and Warm Paper (light).
        static let safelight = LinearGradient(
            colors: [Colors.accent, Colors.accent2],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
