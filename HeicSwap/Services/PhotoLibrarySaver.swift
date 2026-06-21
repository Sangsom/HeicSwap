//
//  PhotoLibrarySaver.swift
//  HeicSwap
//
//  Saves converted images into the user's photo library from the Results sheet (task 5.4), using
//  the **add-only** authorization (`PHAccessLevel.addOnly`) — the app only ever *writes* photos, it
//  never reads the library, which keeps the permission prompt minimal and matches the privacy
//  promise. PDFs aren't images, so they're filtered out (the user saves those via Files / Share).
//

import Photos

/// Adds image files to the photo library with add-only permission.
///
/// Stateless; the single `save(imageURLs:)` entry point requests authorization on first use and
/// writes each file as a new asset in one change request. The actual library work runs off the
/// main actor inside PhotoKit's async `performChanges`.
enum PhotoLibrarySaver {

    /// Why a save couldn't complete, surfaced to the sheet so it can guide the user.
    enum SaveError: Error, Equatable {
        /// The user declined (or restricted) add-only access — route them to Settings.
        case notAuthorized
        /// Nothing image-typed to save (e.g. a PDF-only run).
        case nothingToSave
        /// PhotoKit rejected the change request.
        case saveFailed
    }

    /// Requests add-only authorization (if needed) and saves each URL as a new photo asset.
    /// Throws `SaveError` so the caller can distinguish "denied" (offer Settings) from a genuine
    /// write failure.
    static func save(imageURLs: [URL]) async throws {
        guard !imageURLs.isEmpty else { throw SaveError.nothingToSave }

        guard await isAddOnlyAuthorized() else { throw SaveError.notAuthorized }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for url in imageURLs {
                    PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            }
        } catch {
            throw SaveError.saveFailed
        }
    }

    /// True once add-only access is granted, requesting it the first time the status is undecided.
    private static func isAddOnlyAuthorized() async -> Bool {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let status = current == .notDetermined
            ? await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            : current
        // Add-only never returns `.limited`; `.authorized` is the only success.
        return status == .authorized
    }
}
