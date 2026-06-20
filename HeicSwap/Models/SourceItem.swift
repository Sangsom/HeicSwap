//
//  SourceItem.swift
//  HeicSwap
//
//  One item queued for conversion. Its source is either a Photos asset (referenced by
//  local identifier — never the photo data) or a file on disk, plus a progress status.
//  Import is built in task 3.5; this type is the shared contract between import, the queue
//  UI (task 5.1), and the engine (task 3.1).
//

import Foundation

/// A single image queued for conversion, identified for use in SwiftUI lists.
///
/// `nonisolated` so the engine can update `status` off the main actor while the queue UI
/// observes it. Carries a *reference* to its source (asset id or file URL), never the pixel
/// data, keeping the type cheap to copy across actor boundaries.
nonisolated struct SourceItem: Identifiable, Sendable, Equatable, Hashable {

    /// Where an item's image comes from.
    enum Source: Sendable, Equatable, Hashable {
        /// A Photos library asset, referenced by `PHAsset.localIdentifier` (not the data).
        case photoLibraryAsset(identifier: String)
        /// A file on disk (Files import, or an iCloud-downloaded original).
        case file(url: URL)
    }

    /// Stable identity for lists and queue updates, independent of the source.
    let id: UUID
    /// Where this item's image is read from.
    let source: Source
    /// Current progress through the pipeline.
    var status: ItemStatus

    init(id: UUID = UUID(), source: Source, status: ItemStatus = .pending) {
        self.id = id
        self.source = source
        self.status = status
    }

    /// Queue an item backed by a Photos library asset, starting `.pending`.
    static func photoLibraryAsset(identifier: String) -> SourceItem {
        SourceItem(source: .photoLibraryAsset(identifier: identifier))
    }

    /// Queue an item backed by a file URL, starting `.pending`.
    static func file(url: URL) -> SourceItem {
        SourceItem(source: .file(url: url))
    }
}

// MARK: - Item Status

/// The lifecycle of a queued item as it moves through import and conversion.
nonisolated enum ItemStatus: Sendable, Equatable, Hashable {
    /// Queued, not yet started.
    case pending
    /// Downloading the original from iCloud (Photos optimized-storage case).
    case downloading
    /// Conversion in progress.
    case converting
    /// Finished successfully.
    case done
    /// Failed; the item stays in the queue so the user can retry or remove it.
    case failed
}
