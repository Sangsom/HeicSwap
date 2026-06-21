//
//  PhotosImportButton.swift
//  HeicSwap
//
//  Reusable Photos entry point for import (task 3.5). Wraps `PhotosPicker` so callers get a
//  multi-select image picker that needs no photo-library permission — selection is scoped to
//  the chosen items — and hands the picked items back through `onPick`. The queue UI (task 5.1)
//  reuses this rather than re-deriving picker plumbing.
//

import PhotosUI
import SwiftUI

struct PhotosImportButton: View {
    /// Maximum number of photos selectable at once; `nil` means unlimited.
    var maxSelectionCount: Int?
    /// Called with the picked items, in selection order, once the sheet is dismissed.
    let onPick: ([PhotosPickerItem]) -> Void

    @State private var selection: [PhotosPickerItem] = []

    var body: some View {
        // The picker's label builder is `@Sendable`, so it holds only a literal label
        // (no main-actor-isolated captures).
        PhotosPicker(
            selection: $selection,
            maxSelectionCount: maxSelectionCount,
            selectionBehavior: .ordered,
            matching: .images
        ) {
            Label("Photos", systemImage: "photo.on.rectangle")
        }
        .onChange(of: selection) { _, newSelection in
            guard !newSelection.isEmpty else { return }
            onPick(newSelection)
            selection = []
        }
    }
}
