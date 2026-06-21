//
//  ImportService.swift
//  HeicSwap
//
//  Brings images into the conversion queue (task 3.5) from two sources — the system
//  `PhotosPicker` and the Files app — materializing each into a local original file the
//  engine (task 3.1) can read by URL. 100% on-device: nothing is ever uploaded.
//
//  iCloud-optimized-storage note (the case the Critic flagged): a Photos pick may be a
//  cloud-only original. We *download* it (never upload) via `PhotosPickerItem`'s
//  completion-handler `loadTransferable`, whose returned `Progress` drives a visible
//  "Downloading from iCloud…" state with real fractional progress — and crucially needs
//  **no photo-library permission** (the picker grants scoped access to the chosen items
//  only). That keeps the "no full-library permission" promise true. We deliberately do *not*
//  use `PHImageManager`/`PHAsset` here: resolving an asset to read its data requires
//  `PHPhotoLibrary` read authorization, which would break that promise.
//
//  Unsupported inputs are flagged and skipped, never crashed: every materialized source is
//  validated as a decodable image (ImageIO) before it joins the queue.
//

import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Errors

/// A reason an import could not be added to the queue. `nonisolated` + `Sendable` so it
/// crosses the loader / UI actor boundary under the app's default `@MainActor` isolation.
nonisolated enum ImportError: Error, Sendable, Equatable, LocalizedError {
    /// The file's type isn't a supported image we can convert.
    case unsupportedType(name: String)
    /// The data was retrieved but couldn't be decoded as an image.
    case unreadableData(name: String)
    /// Reading, downloading, or copying the source failed (I/O, or an offline iCloud original).
    case importFailed(name: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            String(localized: "Not a supported image type")
        case .unreadableData:
            String(localized: "Couldn't read the image")
        case .importFailed:
            String(localized: "Couldn't import this item")
        }
    }
}

// MARK: - In-flight & skipped rows

/// An import still in progress, or one that failed mid-download — surfaced so the UI can show
/// a "Downloading from iCloud…" spinner / percentage or a graceful failure. Files import is a
/// fast local copy, so only Photos imports ever appear here.
struct ActiveImport: Identifiable, Sendable, Equatable {
    let id: UUID
    var label: String
    var status: ItemStatus
    /// Download progress in `0...1`, or `nil` while indeterminate.
    var fractionCompleted: Double?
    /// User-facing message shown when `status == .failed`.
    var message: String?
}

/// An item that was offered for import but skipped because it isn't a usable image.
struct ImportSkip: Identifiable, Sendable, Equatable {
    let id: UUID
    let label: String
    let reason: ImportError
}

// MARK: - Service

/// Orchestrates import and owns the observable queue state. `@MainActor @Observable` so the
/// (future) queue UI (task 5.1) binds directly to `items` / `active` / `skipped`; the actual
/// file work runs off the main actor inside the `nonisolated` loaders.
@MainActor
@Observable
final class ImportService {

    /// The image input types we accept — used to filter the Files importer and to validate
    /// every materialized source. RAW / WebP input is deferred to v1.1.
    nonisolated static let supportedContentTypes: [UTType] =
        [.jpeg, .png, .heic, .heif, .tiff, .gif, .bmp]

    /// Materialized originals, in import order, each ready for the engine (`.file(url:)`, `.pending`).
    private(set) var items: [SourceItem] = []
    /// Imports currently downloading, or failed mid-download (kept so the user can retry/remove).
    private(set) var active: [ActiveImport] = []
    /// Inputs flagged and skipped because they aren't usable images.
    private(set) var skipped: [ImportSkip] = []

    private let photoLoader: PhotoOriginalLoader
    private let fileLoader: FileImportLoader

    init(
        rootDirectory: URL? = nil,
        supportedContentTypes: [UTType] = ImportService.supportedContentTypes
    ) {
        let root = rootDirectory
            ?? FileManager.default.temporaryDirectory.appending(
                path: "Imports", directoryHint: .isDirectory
            )
        self.photoLoader = PhotoOriginalLoader(
            rootDirectory: root, supportedContentTypes: supportedContentTypes
        )
        self.fileLoader = FileImportLoader(
            rootDirectory: root, supportedContentTypes: supportedContentTypes
        )
    }

    // MARK: Photos

    /// Imports the originals behind the picked Photos items, in selection order. Each is
    /// downloaded (from iCloud if optimized-away) with a visible `.downloading` state and
    /// progress, then appended to `items`. Unsupported picks are skipped; a download that
    /// fails (e.g. offline) is left in `active` as `.failed` rather than crashing.
    func importFromPhotos(_ selection: [PhotosPickerItem]) async {
        for item in selection {
            let id = UUID()
            active.append(
                ActiveImport(
                    id: id,
                    label: String(localized: "Photo"),
                    status: .downloading,
                    fractionCompleted: 0
                )
            )

            do {
                let url = try await photoLoader.loadOriginal(from: item) { [weak self] fraction in
                    self?.updateProgress(id: id, fraction: fraction)
                }
                removeActive(id)
                items.append(SourceItem(id: id, source: .file(url: url), status: .pending))
            } catch let error as ImportError {
                removeActive(id)
                skipped.append(ImportSkip(id: id, label: String(localized: "Photo"), reason: error))
            } catch is CancellationError {
                removeActive(id)
            } catch {
                markFailed(id: id, message: String(localized: "Couldn't download from iCloud"))
            }
        }
    }

    // MARK: Files

    /// Imports image files chosen via `.fileImporter`, copying each into local storage. Files
    /// that aren't decodable images are flagged into `skipped` rather than added or crashing.
    func importFromFiles(_ urls: [URL]) async {
        for url in urls {
            let label = url.lastPathComponent
            do {
                let destination = try await fileLoader.importFile(at: url)
                items.append(SourceItem(source: .file(url: destination), status: .pending))
            } catch let error as ImportError {
                skipped.append(ImportSkip(id: UUID(), label: label, reason: error))
            } catch {
                skipped.append(
                    ImportSkip(id: UUID(), label: label, reason: .importFailed(name: label))
                )
            }
        }
    }

    // MARK: Mutation

    /// Removes a ready item, a finished/failed active row, or a skipped entry by id.
    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        active.removeAll { $0.id == id }
        skipped.removeAll { $0.id == id }
    }

    /// Clears the skipped list (e.g. after the user has acknowledged it).
    func clearSkipped() {
        skipped.removeAll()
    }

    /// Empties the whole queue — ready items, in-flight rows, and skipped entries — backing the
    /// queue UI's "clear all" (task 5.1). In-flight `loadTransferable` downloads aren't cancelled,
    /// so a download that completes after this call still appends its finished item to the queue.
    func removeAll() {
        items.removeAll()
        active.removeAll()
        skipped.removeAll()
    }

    private func updateProgress(id: UUID, fraction: Double) {
        guard let index = active.firstIndex(where: { $0.id == id }) else { return }
        active[index].fractionCompleted = fraction
    }

    private func markFailed(id: UUID, message: String) {
        guard let index = active.firstIndex(where: { $0.id == id }) else { return }
        active[index].status = .failed
        active[index].message = message
    }

    private func removeActive(_ id: UUID) {
        active.removeAll { $0.id == id }
    }
}

// MARK: - Photos loader

/// Downloads a picked photo's original to a local file, reporting progress. `nonisolated` so
/// the data validation and disk write run off the main actor (the type would otherwise inherit
/// the project's default `@MainActor` isolation).
nonisolated struct PhotoOriginalLoader {
    let rootDirectory: URL
    let supportedContentTypes: [UTType]

    /// Materializes `item`'s original image to a unique local file and returns its URL.
    ///
    /// Uses the completion-handler `loadTransferable`, whose returned `Progress` is observed to
    /// drive `onProgress` (real fractional progress for an iCloud download; a quick 0→1 for an
    /// on-device original). Throws `ImportError.unreadableData` / `.unsupportedType` if the
    /// result isn't a decodable, supported image; rethrows the system error (e.g. offline) so
    /// the caller can present a graceful failure.
    func loadOriginal(
        from item: PhotosPickerItem,
        onProgress: @escaping @MainActor (Double) -> Void
    ) async throws -> URL {
        let observer = ProgressObserver()
        defer { observer.cancel() }

        let data: Data = try await withCheckedThrowingContinuation { continuation in
            let progress = item.loadTransferable(type: Data.self) { result in
                switch result {
                case .success(let data?):
                    continuation.resume(returning: data)
                case .success(nil):
                    continuation.resume(throwing: ImportError.unreadableData(name: "Photo"))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            observer.observe(progress) { fraction in
                Task { @MainActor in onProgress(fraction) }
            }
        }

        guard let imageType = Self.imageType(of: data) else {
            throw ImportError.unreadableData(name: "Photo")
        }
        guard supportedContentTypes.contains(where: { imageType.conforms(to: $0) }) else {
            throw ImportError.unsupportedType(name: "Photo")
        }

        let runDirectory = try makeRunDirectory()
        let fileExtension = imageType.preferredFilenameExtension ?? "img"
        let destination = runDirectory.appending(path: "original.\(fileExtension)")
        do {
            try data.write(to: destination)
        } catch {
            throw ImportError.importFailed(name: "Photo")
        }
        return destination
    }

    private func makeRunDirectory() throws -> URL {
        let directory = rootDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// The decoded image's uniform type, or `nil` if `data` isn't a decodable image.
    private static func imageType(of data: Data) -> UTType? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let identifier = CGImageSourceGetType(source) else {
            return nil
        }
        return UTType(identifier as String)
    }
}

/// Owns the KVO subscription on a `loadTransferable` `Progress` and forwards `fractionCompleted`.
/// `nonisolated` (the project defaults types to `@MainActor`) so the loader can drive it off the
/// main actor, and `@unchecked Sendable` because it guards its non-`Sendable` observation token
/// behind a lock so it can be created on one actor and torn down from the (background) handler.
private nonisolated final class ProgressObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var observation: NSKeyValueObservation?

    func observe(_ progress: Progress, onFraction: @escaping @Sendable (Double) -> Void) {
        lock.withLock {
            observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { progress, _ in
                onFraction(progress.fractionCompleted)
            }
        }
    }

    func cancel() {
        lock.withLock {
            observation?.invalidate()
            observation = nil
        }
    }
}

// MARK: - Files loader

/// Validates and copies a security-scoped file into local storage. `nonisolated` so the copy
/// runs off the main actor.
nonisolated struct FileImportLoader {
    let rootDirectory: URL
    let supportedContentTypes: [UTType]

    /// Copies `url` into a unique local directory and returns the copy's URL, preserving the
    /// original file name. Throws `ImportError.unsupportedType` for anything that isn't a
    /// decodable supported image (so the caller flags and skips it), or `.importFailed` on I/O error.
    func importFile(at url: URL) async throws -> URL {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }

        guard isSupportedImage(at: url) else {
            throw ImportError.unsupportedType(name: url.lastPathComponent)
        }

        do {
            let runDirectory = rootDirectory.appending(
                path: UUID().uuidString, directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
            let destination = runDirectory.appending(path: url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            throw ImportError.importFailed(name: url.lastPathComponent)
        }
    }

    /// True if ImageIO can decode `url` as one of the supported image types.
    func isSupportedImage(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let identifier = CGImageSourceGetType(source),
              let type = UTType(identifier as String) else {
            return false
        }
        return supportedContentTypes.contains { type.conforms(to: $0) }
    }
}
