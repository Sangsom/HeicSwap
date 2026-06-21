//
//  ConvertViewModel.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 21/06/2026.
//

import PhotosUI
import SwiftUI

/// State owner for the Convert screen (task 5.1): the queue of images to convert, plus the
/// add / remove / clear actions that mutate it.
///
/// Wraps `ImportService` (task 3.5) and re-exposes its observable queue so the view binds to one
/// object. Phase 5 grows this — conversion options (5.2) and the convert action (5.3) land here —
/// which is why the screen talks to a view model rather than the service directly.
@MainActor
@Observable
final class ConvertViewModel {

    private let importService: ImportService

    init(importService: ImportService = ImportService()) {
        self.importService = importService
    }

    /// Materialized items ready to convert, in import order.
    var items: [SourceItem] { importService.items }

    /// Imports still downloading (the Photos / iCloud-optimized case) or failed mid-download.
    var activeImports: [ActiveImport] { importService.active }

    /// Inputs flagged and skipped because they aren't usable images.
    var skipped: [ImportSkip] { importService.skipped }

    /// True when there's nothing to show — no ready items and nothing downloading. Drives the
    /// empty state. (Skips alone don't count: an all-skipped import should fall back to empty.)
    var isEmpty: Bool {
        items.isEmpty && activeImports.isEmpty
    }

    // MARK: Add

    /// Imports the picked Photos items (downloading iCloud originals on demand), appending them
    /// to the queue in selection order.
    func addFromPhotos(_ selection: [PhotosPickerItem]) async {
        await importService.importFromPhotos(selection)
    }

    /// Imports the chosen image files, appending them to the queue in order.
    func addFromFiles(_ urls: [URL]) async {
        await importService.importFromFiles(urls)
    }

    // MARK: Remove

    /// Removes a single queued item (or a failed/skipped row) by id; the rest are untouched.
    func remove(_ id: SourceItem.ID) {
        importService.remove(id)
    }

    /// Empties the entire queue.
    func clearAll() {
        importService.removeAll()
    }

    /// Dismisses the skipped-items note.
    func clearSkipped() {
        importService.clearSkipped()
    }
}
