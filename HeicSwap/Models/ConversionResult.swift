//
//  ConversionResult.swift
//  HeicSwap
//
//  One finished output from a conversion run, paired with the input size it came from, so the
//  Results sheet (task 5.4) can show each output, its resulting size, and how much space the run
//  saved. A plain value type: it describes a result and holds no behavior.
//

import Foundation

/// A single output produced by a conversion run: the written file, its size, and the size of the
/// input(s) it replaced.
///
/// `nonisolated` so the off-main-actor engine / PDF builder and the main-actor UI can share it
/// freely under the app's default `@MainActor` isolation. Identified by its output URL, which is
/// collision-free within a run (the engine disambiguates duplicate names, and each run writes to a
/// unique directory).
///
/// `originalBytes` is the source that produced this output — the single input for an image
/// transcode, or the *sum* of all inputs for a combined PDF — so `bytesSaved` reads correctly for
/// both the N→N and N→1 cases.
nonisolated struct ConversionResult: Identifiable, Sendable, Equatable, Hashable {

    /// The written output file on disk (in the run's temp directory).
    let outputURL: URL
    /// Total bytes of the input(s) this output was produced from.
    let originalBytes: Int
    /// Bytes of the written output file.
    let outputBytes: Int

    var id: URL { outputURL }

    init(outputURL: URL, originalBytes: Int, outputBytes: Int) {
        self.outputURL = outputURL
        self.originalBytes = max(0, originalBytes)
        self.outputBytes = max(0, outputBytes)
    }

    /// The output file name shown in the list, e.g. "IMG_0421.jpg".
    var displayName: String { outputURL.lastPathComponent }

    /// Whether this output is the combined PDF (which can't be saved to Photos and has no
    /// ImageIO thumbnail).
    var isPDF: Bool { outputURL.pathExtension.lowercased() == "pdf" }

    /// Bytes shaved off versus the input(s); `0` when the output grew (e.g. a PNG re-encode), so a
    /// run never reports negative savings.
    var bytesSaved: Int { max(0, originalBytes - outputBytes) }
}
