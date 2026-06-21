//
//  QueueLayout.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 21/06/2026.
//

import Foundation

/// Pure layout math for the Convert queue's bounded preview grid (task 5.1).
///
/// The Convert screen keeps the whole app on one screen (design spec §3), so the queue shows a
/// capped preview: the first thumbnails plus a single "+N" overflow tile standing in for the
/// rest. Expanding swaps that for the full, scrollable queue. Kept as a free function — no view
/// state — so the boundary behaviour is unit-tested directly. `nonisolated` (the project defaults
/// types to `@MainActor`) so it's callable as pure math from any context, including tests.
nonisolated enum QueueLayout {

    /// Splits `total` queued items into the number of real thumbnails to render and the count
    /// folded into the "+N" tile.
    ///
    /// - When expanded, or when everything already fits within `cap`, all items show and overflow
    ///   is `0`.
    /// - Otherwise the last cell is reserved for "+N", so `cap - 1` thumbnails render and the
    ///   remaining `total - (cap - 1)` collapse into the overflow tile.
    ///
    /// - Parameters:
    ///   - total: Number of items in the queue (`>= 0`).
    ///   - cap: Number of grid cells the collapsed preview may use (`>= 1`).
    ///   - isExpanded: Whether the user has expanded the grid to show everything.
    /// - Returns: `visible` thumbnails to render and the `overflow` count for the "+N" tile.
    static func split(total: Int, cap: Int, isExpanded: Bool) -> (visible: Int, overflow: Int) {
        guard !isExpanded, total > cap else { return (total, 0) }
        let visible = cap - 1
        return (visible, total - visible)
    }
}
