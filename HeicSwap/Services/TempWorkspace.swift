//
//  TempWorkspace.swift
//  HeicSwap
//
//  The single home for the app's temporary working files, and the one place that purges them
//  (task 10.3). Imported originals and conversion/PDF outputs all live under one root in the
//  system temporary directory, so cleanup is deterministic:
//
//  - a finished run's outputs are reclaimed once they're no longer reachable (a new run starts,
//    the queue is cleared, or the app is backgrounded),
//  - the whole workspace is wiped on a cold launch, clearing anything a previous (possibly killed)
//    session left behind,
//  - and the imported originals are dropped when the queue that referenced them is emptied.
//
//  Centralizing the layout here means `ConversionEngine`, `PDFBuilder`, and `ImportService` no
//  longer each invent their own temp folder, and a single `purgeAll()` reclaims everything.
//

import Foundation

/// Owns the temp-directory layout and purges it. Every member is `nonisolated` — they touch only
/// the thread-safe `FileManager` — so callers invoke them off the main actor (file IO) without an
/// actor hop. Directories are recreated on demand by the writers (`createDirectory(…,
/// withIntermediateDirectories: true)`), so removing a root between runs is always safe.
nonisolated enum TempWorkspace {

    /// The app's single temp root. Everything HeicSwap writes to the temporary directory lives
    /// under here, so wiping it is one `removeItem`.
    static let root = FileManager.default.temporaryDirectory
        .appending(path: "HeicSwap", directoryHint: .isDirectory)

    /// Imported originals — one subdirectory per imported item — that the engine reads by URL.
    static let importsRoot = root
        .appending(path: "Imports", directoryHint: .isDirectory)

    /// Transcoded image outputs — one subdirectory per conversion run.
    static let conversionOutputsRoot = root
        .appending(path: "ConversionEngine", directoryHint: .isDirectory)

    /// Assembled PDF outputs — one subdirectory per build.
    static let pdfOutputsRoot = root
        .appending(path: "PDFBuilder", directoryHint: .isDirectory)

    /// Removes every conversion and PDF output, leaving imports intact. Safe whenever no run is in
    /// flight: each run writes into its own fresh subdirectory, so this only drops finished work.
    static func purgeOutputs() {
        remove(conversionOutputsRoot)
        remove(pdfOutputsRoot)
    }

    /// Removes every imported original. Call once the queue that referenced them is emptied.
    static func purgeImports() {
        remove(importsRoot)
    }

    /// Wipes the entire workspace — imports and outputs alike. Used at launch to clear orphans from
    /// a prior session, and whenever the whole working set is discarded.
    static func purgeAll() {
        remove(root)
    }

    /// Removes one run's directory by URL — a finished run's own output folder, abandoned when the
    /// next run starts. Missing directories are ignored.
    static func removeTree(at directory: URL) {
        remove(directory)
    }

    private static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
