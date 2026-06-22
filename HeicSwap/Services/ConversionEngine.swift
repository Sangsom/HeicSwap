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
//  Scope note: 3.1 implemented the format + quality transcode; 3.2 added resizing —
//  `.maxDimension` downscale-on-load and `.targetBytes` quality binary search; 3.3 adds
//  opt-in EXIF/GPS/maker-note stripping on the write path. Image→PDF assembly (3.4) still
//  layers on in its own task. With stripping off (the default), the no-resize path stays a
//  faithful color- and metadata-preserving passthrough.
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

    /// Upper bound on quality-search encodes for `ResizeMode.targetBytes`. Eight halvings
    /// resolve quality to ~1/256 — finer than the JPEG encoder's own granularity — so the
    /// search converges well within the cap (PRD / task 3.2: "cap ~8 iterations"). A faithful
    /// full-quality probe runs first as a fast path, so the worst case is one encode more.
    static let maxQualitySearchIterations = 8

    /// Root directory outputs are written under. Each run gets a unique subdirectory inside it.
    /// Defaults to the shared `TempWorkspace`, which owns the temp layout and its deterministic
    /// purge (task 10.3).
    private let outputDirectory: URL

    init(outputDirectory: URL? = nil) {
        self.outputDirectory = outputDirectory ?? TempWorkspace.conversionOutputsRoot
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

    /// Builds the destination properties for a transcode that copies the source frame via
    /// `…AddImageFromSource`. Sets the lossy-compression quality for quality-bearing formats and,
    /// when `options.stripsMetadata` is set, marks the identifying metadata dictionaries for
    /// removal so the output is written clean. Pass `quality` to override `options.quality` (the
    /// target-size search drives quality itself).
    private nonisolated static func sourceCopyProperties(
        options: ConversionOptions, quality: Double? = nil
    ) -> [CFString: Any] {
        var properties: [CFString: Any] = [:]
        if options.format.usesQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality ?? options.quality
        }
        if options.stripsMetadata {
            // Top-level ImageIO dictionaries that carry identifying metadata — camera/EXIF data,
            // GPS coordinates, the TIFF make/model/software/timestamp, and vendor maker notes.
            // Marking each `kCFNull` drops it from the copied output (task 3.3). ImageIO still
            // retains the structurally-necessary display fields: nulling the TIFF dictionary keeps
            // only its `Orientation` tag (so the image stays upright), and the embedded color
            // profile (ICC) is preserved independently — verified against a real-photo-shaped
            // fixture. Removing the Exif dictionary also removes the Exif maker-note tag nested
            // inside it; the standalone vendor maker-note dictionaries are siblings, so they are
            // listed explicitly. (A local rather than a static: `[CFString]` is not `Sendable`, so
            // it can't be a `nonisolated` stored constant under Swift 6 strict concurrency.)
            let strippedKeys: [CFString] = [
                kCGImagePropertyExifDictionary,
                kCGImagePropertyExifAuxDictionary,
                kCGImagePropertyGPSDictionary,
                kCGImagePropertyTIFFDictionary,
                kCGImagePropertyIPTCDictionary,
                kCGImagePropertyMakerAppleDictionary,
                kCGImagePropertyMakerCanonDictionary,
                kCGImagePropertyMakerNikonDictionary,
                kCGImagePropertyMakerMinoltaDictionary,
                kCGImagePropertyMakerFujiDictionary,
                kCGImagePropertyMakerOlympusDictionary,
                kCGImagePropertyMakerPentaxDictionary,
            ]
            for key in strippedKeys { properties[key] = kCFNull }
        }
        return properties
    }

    /// The actual transcode — `nonisolated` so batch items run in parallel off the actor,
    /// and synchronous so each item's CF temporaries drain inside its own `autoreleasepool`,
    /// keeping batch memory bounded. Dispatches on `resizeMode`:
    ///
    /// - `.none` — a faithful passthrough copy (preserves color and orientation; metadata too,
    ///   unless `options.stripsMetadata` drops the identifying dictionaries).
    /// - `.maxDimension` — downscale-on-load via the ImageIO thumbnail generator.
    /// - `.targetBytes` — a bounded quality binary search that lands at/under the target.
    nonisolated static func encode(
        source: URL, to destination: URL, options: ConversionOptions
    ) throws {
        guard options.format != .pdf else {
            throw ConversionError.unsupportedOutputFormat(.pdf)
        }

        try autoreleasepool {
            switch options.resizeMode {
            case .none:
                try encodePassthrough(source: source, to: destination, options: options)
            case .maxDimension(let pixels):
                try encodeDownscaled(
                    source: source, to: destination, maxPixels: pixels, options: options
                )
            case .targetBytes(let targetBytes):
                try encodeToTargetBytes(
                    source: source, to: destination, targetBytes: targetBytes, options: options
                )
            }
        }
    }

    /// Direct frame copy. `CGImageDestinationAddImageFromSource` carries the source frame's
    /// properties (embedded color profile, orientation, metadata) straight into the output
    /// without us holding a decoded bitmap — faithful color, minimal memory. When
    /// `options.stripsMetadata` is set, the identifying dictionaries (Exif, GPS, maker notes)
    /// are nulled in the override so they are dropped from the copy.
    private nonisolated static func encodePassthrough(
        source: URL, to destination: URL, options: ConversionOptions
    ) throws {
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

        let properties = sourceCopyProperties(options: options)

        CGImageDestinationAddImageFromSource(
            imageDestination, imageSource, 0, properties as CFDictionary
        )

        guard CGImageDestinationFinalize(imageDestination) else {
            throw ConversionError.encodingFailed(destination)
        }
    }

    /// Downscale so the longest edge is at most `maxPixels`, preserving aspect ratio. ImageIO's
    /// thumbnail generator downsamples *as it decodes*, so a 48 MP source never lands in memory
    /// at full resolution — this is what keeps peak memory bounded (task 3.2 AC3). The transform
    /// is applied so the output is upright; a source already within the limit is never upscaled.
    ///
    /// The thumbnail is a fresh bitmap that inherits none of the source's Exif/GPS/maker-note
    /// dictionaries, so this path emits metadata-clean output regardless of `stripsMetadata` —
    /// stripping is satisfied here by construction (task 3.3).
    private nonisolated static func encodeDownscaled(
        source: URL, to destination: URL, maxPixels: Int, options: ConversionOptions
    ) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0 else {
            throw ConversionError.sourceUnreadable(source)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixels),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let downsized = CGImageSourceCreateThumbnailAtIndex(
            imageSource, 0, thumbnailOptions as CFDictionary
        ) else {
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

        CGImageDestinationAddImage(imageDestination, downsized, properties as CFDictionary)

        guard CGImageDestinationFinalize(imageDestination) else {
            throw ConversionError.encodingFailed(destination)
        }
    }

    /// Re-encode at the highest quality whose output is at most `targetBytes` (e.g. "under 2 MB"),
    /// the differentiated feature the native share sheet can't do. A full-quality probe runs
    /// first; if it already fits we keep it untouched, otherwise a bounded binary search over
    /// quality converges to the largest quality that fits. Each round encodes the source frame
    /// into memory via `…AddImageFromSource` — no decoded bitmap is held, so memory stays bounded
    /// even for very large photos. Lossless output (PNG) can't be sized by quality, so it falls
    /// back to a single faithful encode.
    private nonisolated static func encodeToTargetBytes(
        source: URL, to destination: URL, targetBytes: Int, options: ConversionOptions
    ) throws {
        guard options.format.usesQuality else {
            // Quality has no effect on a lossless codec; emit one faithful copy.
            try encodePassthrough(source: source, to: destination, options: options)
            return
        }

        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0 else {
            throw ConversionError.sourceUnreadable(source)
        }

        let type = options.format.contentType.identifier as CFString
        let target = max(0, targetBytes)

        /// Encodes the frame at `quality` into memory, returning the encoded bytes. Honors
        /// `options.stripsMetadata` — every probe writes the same clean (or faithful) metadata
        /// the final output will carry, so size estimates match the file that lands on disk.
        func encodedData(quality: Double) throws -> Data {
            let data = NSMutableData()
            guard let imageDestination = CGImageDestinationCreateWithData(
                data as CFMutableData, type, 1, nil
            ) else {
                throw ConversionError.destinationUnavailable(destination)
            }
            CGImageDestinationAddImageFromSource(
                imageDestination, imageSource, 0,
                sourceCopyProperties(options: options, quality: quality) as CFDictionary
            )
            guard CGImageDestinationFinalize(imageDestination) else {
                throw ConversionError.encodingFailed(destination)
            }
            return data as Data
        }

        // Fast path: if full quality already fits, never degrade.
        let fullQuality = try encodedData(quality: 1.0)
        var best = fullQuality

        if fullQuality.count > target {
            // Binary-search the largest quality whose encoded size is within the target.
            var low = 0.0
            var high = 1.0
            var fitting: Data?
            for _ in 0..<maxQualitySearchIterations {
                let mid = (low + high) / 2
                let candidate = try encodedData(quality: mid)
                if candidate.count <= target {
                    fitting = candidate
                    low = mid // room to spend on quality
                } else {
                    high = mid // must compress harder
                }
            }
            // If even minimum quality overshoots (target below the format's floor), emit the
            // smallest we can produce — best effort rather than a failure.
            best = try fitting ?? encodedData(quality: 0.0)
        }

        do {
            try best.write(to: destination, options: .atomic)
        } catch {
            throw ConversionError.encodingFailed(destination)
        }
    }
}
