//
//  ConversionEngine.swift
//  HeicSwap
//
//  The on-device conversion backbone (task 3.1). An `actor` that transcodes
//  HEIC / HEIF / PNG / JPG → JPG / PNG / HEIC via ImageIO, preserving the embedded
//  color profile, and runs batches through a bounded `TaskGroup` with per-item failure
//  isolation and progress. 100% offline — ImageIO touches only the local file system,
//  this type opens no sockets (the guarantee is locked by the CI test in task 10.4).
//
//  Scope note: 3.1 implements the format + quality transcode only. Resize (3.2),
//  metadata stripping (3.3), and image→PDF assembly (3.4) layer onto this engine in
//  their own tasks; the encode path below preserves color *and* metadata untouched so
//  those features can branch from a faithful passthrough.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Errors

/// A failure converting a single image. Carries the offending URL so a batch can report
/// which item failed without aborting the rest. `nonisolated` + `Sendable` so it crosses
/// the engine / UI actor boundary under the app's default `@MainActor` isolation.
nonisolated enum ConversionError: Error, Sendable, Equatable {
    /// The source could not be read as an image (missing, unreadable, or not an image).
    case sourceUnreadable(URL)
    /// The requested output format isn't produced by this engine — PDF is assembled by
    /// the PDFKit path in task 3.4, not transcoded here.
    case unsupportedOutputFormat(OutputFormat)
    /// ImageIO could not create a destination at the output URL.
    case destinationUnavailable(URL)
    /// Encoding or finalizing the output failed.
    case encodingFailed(URL)
    /// The work was cancelled before the item was converted.
    case cancelled
}

// MARK: - Outcome

/// The result of converting one source in a batch, tagged with its position in the input
/// so callers can correlate it back to their queue (e.g. map onto a `SourceItem`). Carries
/// either the output file URL or the `ConversionError` — never both.
nonisolated struct ConversionOutcome: Sendable, Identifiable {
    /// Index of the source in the array passed to `convertBatch`.
    let index: Int
    /// The source that was converted.
    let source: URL
    /// Success with the written output URL, or the isolated failure.
    let result: Result<URL, ConversionError>

    var id: Int { index }

    /// Output URL on success, `nil` on failure.
    var output: URL? { try? result.get() }

    /// Whether this item converted successfully.
    var didSucceed: Bool { output != nil }
}

// MARK: - Engine

/// Converts images on-device with ImageIO. An `actor` so it owns its output-directory
/// lifecycle as a single isolation domain; the CPU-bound encode itself runs in a
/// `nonisolated` function so batch items convert in parallel rather than serializing on
/// the actor.
actor ConversionEngine {

    /// Default in-flight conversion count, clamped to the task's 2–4 band. Image transcodes
    /// are memory-heavy, so concurrency is deliberately bounded rather than core-count-wide.
    static var defaultConcurrency: Int {
        min(4, max(2, ProcessInfo.processInfo.activeProcessorCount))
    }

    /// Root directory outputs are written under. Each run gets a unique subdirectory inside
    /// it. Defaults to a dedicated folder in the system temporary directory; temp-file
    /// purging is handled in task 10.3.
    private let outputDirectory: URL

    init(outputDirectory: URL? = nil) {
        self.outputDirectory = outputDirectory
            ?? FileManager.default.temporaryDirectory.appending(
                path: "ConversionEngine", directoryHint: .isDirectory
            )
    }

    // MARK: Single

    /// Converts one image file and returns the output URL. Throws `ConversionError` on
    /// failure. Honors cooperative cancellation.
    func convert(_ source: URL, with options: ConversionOptions) async throws -> URL {
        try Task.checkCancellation()
        let runDirectory = try makeRunDirectory()
        let destination = uniqueOutputURL(
            for: source, format: options.format, in: runDirectory, claimed: []
        )
        try Self.encode(source: source, to: destination, options: options)
        return destination
    }

    // MARK: Batch

    /// Converts many files with bounded concurrency. One failing item is isolated — it
    /// produces a `.failure` outcome while the rest complete. `onItemCompleted` fires once
    /// per item as it finishes (out of input order, due to concurrency); the returned array
    /// is sorted back into input order.
    ///
    /// Only `maxConcurrent` items are ever decoded at once, so a large batch never loads the
    /// whole set into memory.
    @discardableResult
    func convertBatch(
        _ sources: [URL],
        with options: ConversionOptions,
        maxConcurrent: Int = ConversionEngine.defaultConcurrency,
        onItemCompleted: (@Sendable (ConversionOutcome) -> Void)? = nil
    ) async -> [ConversionOutcome] {
        guard !sources.isEmpty else { return [] }

        // Resolve all output URLs up front so duplicate source names can't collide and no
        // per-item actor hop is needed inside the group.
        let runDirectory: URL
        do {
            runDirectory = try makeRunDirectory()
        } catch {
            // Without an output directory nothing can be written; fail every item in isolation.
            let outcomes = sources.enumerated().map { index, source in
                ConversionOutcome(
                    index: index, source: source,
                    result: .failure(.destinationUnavailable(self.outputDirectory))
                )
            }
            outcomes.forEach { onItemCompleted?($0) }
            return outcomes
        }
        let destinations = outputURLs(for: sources, format: options.format, in: runDirectory)

        let limit = max(1, min(maxConcurrent, sources.count))

        return await withTaskGroup(of: ConversionOutcome.self) { group in
            var nextIndex = 0

            func addTask(at index: Int) {
                let source = sources[index]
                let destination = destinations[index]
                group.addTask {
                    if Task.isCancelled {
                        return ConversionOutcome(
                            index: index, source: source, result: .failure(.cancelled)
                        )
                    }
                    let result: Result<URL, ConversionError>
                    do {
                        try Self.encode(source: source, to: destination, options: options)
                        result = .success(destination)
                    } catch let error as ConversionError {
                        result = .failure(error)
                    } catch {
                        result = .failure(.encodingFailed(destination))
                    }
                    return ConversionOutcome(index: index, source: source, result: result)
                }
            }

            // Seed the window, then top it up as each item completes — keeps exactly `limit`
            // conversions in flight.
            while nextIndex < limit {
                addTask(at: nextIndex)
                nextIndex += 1
            }

            var outcomes: [ConversionOutcome] = []
            outcomes.reserveCapacity(sources.count)
            for await outcome in group {
                outcomes.append(outcome)
                onItemCompleted?(outcome)
                if nextIndex < sources.count {
                    addTask(at: nextIndex)
                    nextIndex += 1
                }
            }

            return outcomes.sorted { $0.index < $1.index }
        }
    }

    // MARK: Output paths

    /// Creates a fresh unique subdirectory for one run's outputs.
    private func makeRunDirectory() throws -> URL {
        let directory = outputDirectory.appending(
            path: UUID().uuidString, directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        return directory
    }

    /// Output URLs for a batch, preserving source base names and disambiguating duplicates
    /// (`photo.heic` + `photo.png` → `photo.jpg` + `photo-2.jpg`).
    private func outputURLs(for sources: [URL], format: OutputFormat, in directory: URL) -> [URL] {
        var claimed = Set<String>()
        return sources.map { source in
            let url = uniqueOutputURL(for: source, format: format, in: directory, claimed: claimed)
            claimed.insert(url.lastPathComponent)
            return url
        }
    }

    /// A collision-free output URL: the source's base name with the target extension, suffixed
    /// `-2`, `-3`, … if that name is already `claimed`.
    private func uniqueOutputURL(
        for source: URL, format: OutputFormat, in directory: URL, claimed: Set<String>
    ) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        let safeBase = base.isEmpty ? "image" : base
        let ext = format.fileExtension

        var candidate = "\(safeBase).\(ext)"
        var suffix = 2
        while claimed.contains(candidate) {
            candidate = "\(safeBase)-\(suffix).\(ext)"
            suffix += 1
        }
        return directory.appending(path: candidate)
    }

    // MARK: ImageIO

    /// The actual transcode — `nonisolated` so batch items run in parallel off the actor,
    /// and synchronous so each item's CF temporaries drain inside its own `autoreleasepool`,
    /// keeping batch memory bounded.
    ///
    /// Uses `CGImageDestinationAddImageFromSource`, which copies the source frame's properties
    /// (embedded color profile, orientation, metadata) straight into the output without us
    /// holding a decoded bitmap — faithful color, minimal memory.
    nonisolated static func encode(
        source: URL, to destination: URL, options: ConversionOptions
    ) throws {
        guard options.format != .pdf else {
            throw ConversionError.unsupportedOutputFormat(.pdf)
        }

        try autoreleasepool {
            guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
                  CGImageSourceGetCount(imageSource) > 0 else {
                throw ConversionError.sourceUnreadable(source)
            }

            let type = options.format.contentType.identifier as CFString
            guard let imageDestination = CGImageDestinationCreateWithURL(
                destination as CFURL, type, 1, nil
            ) else {
                throw ConversionError.destinationUnavailable(destination)
            }

            var properties: [CFString: Any] = [:]
            if options.format.usesQuality {
                properties[kCGImageDestinationLossyCompressionQuality] = options.quality
            }

            CGImageDestinationAddImageFromSource(
                imageDestination, imageSource, 0, properties as CFDictionary
            )

            guard CGImageDestinationFinalize(imageDestination) else {
                throw ConversionError.encodingFailed(destination)
            }
        }
    }
}
