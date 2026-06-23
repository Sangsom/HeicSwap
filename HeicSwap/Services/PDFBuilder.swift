//
//  PDFBuilder.swift
//  HeicSwap
//
//  Image → multi-page PDF assembly (task 3.4) — the top ASO acquisition surface
//  ("convert image to pdf"). An `actor` that turns N images into a single multi-page
//  PDF, one image per page, in queue order, 100% on-device.
//
//  This is the N→1 counterpart to `ConversionEngine`'s N→N transcode — a genuinely
//  different operation (which is why the engine *rejects* `.pdf`), so it lives in its
//  own service rather than the `encode` path.
//
//  Renderer choice: `UIGraphicsPDFRenderer.writePDF(to:)` (allowed by the task's developer
//  instructions) streams each page straight to the destination file, and each source is
//  loaded *downscaled* via ImageIO's thumbnail generator — so only one bounded bitmap is
//  ever in memory and the whole PDF is never held at once. That is what keeps memory
//  bounded for many large images (AC3). PDFKit's in-memory `PDFDocument` would hold every
//  page's image until written, so it loses on exactly the memory axis this task cares about.
//

import Foundation
import ImageIO
import UIKit

// MARK: - Errors

/// A failure assembling a PDF. `nonisolated` + `Sendable` so it crosses the builder / UI
/// actor boundary under the app's default `@MainActor` isolation.
nonisolated enum PDFBuilderError: Error, Sendable, Equatable {
    /// No page could be produced — the input was empty or every source was unreadable.
    case noReadableImages
    /// The PDF could not be written at the destination (I/O failure).
    case renderingFailed(URL)
    /// The build was cancelled before it finished; any partial output is discarded.
    case cancelled
}

// MARK: - Builder

/// Assembles images into a single multi-page PDF on-device. An `actor` so it owns its
/// output-directory lifecycle as one isolation domain; the page rendering runs in a
/// `nonisolated` function that loads each image downscaled and streams pages to disk.
actor PDFBuilder {

    /// Cap on a page's longest edge, in pixels (treated as PDF points). Each source is
    /// downsampled to this bound before it is drawn, so a 48 MP photo never lands in memory
    /// at full resolution and the PDF stays a reasonable size. 2048 matches the resize
    /// defaults used elsewhere in the app and is plenty for on-screen viewing and print.
    static let defaultMaxPageDimension = 2048

    /// Default output file name when the caller doesn't supply one.
    static let defaultFileName = "Combined.pdf"

    /// Root directory PDFs are written under; each build gets a unique subdirectory inside it.
    /// Defaults to the shared `TempWorkspace`, which owns the temp layout and its deterministic
    /// purge (task 10.3).
    private let outputDirectory: URL

    init(outputDirectory: URL? = nil) {
        self.outputDirectory = outputDirectory ?? TempWorkspace.pdfOutputsRoot
    }

    /// Builds a single multi-page PDF from `sources`, one page per image, in the order given,
    /// and returns the output file URL.
    ///
    /// Each page is sized to its image's aspect ratio (capped to `maxPageDimension`). Sources
    /// that can't be decoded are skipped rather than aborting the whole document; if that leaves
    /// no pages (empty input or every source unreadable) `PDFBuilderError.noReadableImages` is
    /// thrown. `onPageRendered` fires once per successfully drawn page with the source's index,
    /// for progress reporting. Honors cooperative cancellation.
    func buildPDF(
        from sources: [URL],
        maxPageDimension: Int = PDFBuilder.defaultMaxPageDimension,
        fileName: String = PDFBuilder.defaultFileName,
        onPageRendered: (@Sendable (Int) -> Void)? = nil
    ) async throws -> URL {
        try Task.checkCancellation()
        guard !sources.isEmpty else { throw PDFBuilderError.noReadableImages }

        let runDirectory = try makeRunDirectory()
        let destination = runDirectory.appending(path: Self.sanitizedFileName(fileName))

        try Self.render(
            sources: sources,
            to: destination,
            maxPageDimension: maxPageDimension,
            onPageRendered: onPageRendered
        )
        return destination
    }

    // MARK: Output paths

    /// Creates a fresh unique subdirectory for one build's output.
    private func makeRunDirectory() throws -> URL {
        let directory = outputDirectory.appending(
            path: UUID().uuidString, directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        return directory
    }

    /// Normalizes a caller-supplied name to a safe `.pdf` file name (no path separators).
    private nonisolated static func sanitizedFileName(_ name: String) -> String {
        let withoutSeparators = name.replacingOccurrences(of: "/", with: "-")
        let base = (withoutSeparators as NSString).deletingPathExtension
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeBase = trimmed.isEmpty ? "Combined" : trimmed
        return "\(safeBase).pdf"
    }

    // MARK: Rendering

    /// Streams the multi-page PDF to `destination`. `nonisolated` so the CPU/IO-bound render
    /// runs off the main actor, and synchronous so each page's decoded bitmap drains inside its
    /// own `autoreleasepool` before the next page loads — keeping peak memory to one image.
    ///
    /// Pages are appended in input order. A source that fails to decode is skipped; if no page
    /// is ever written the (empty, invalid) file is removed and `.noReadableImages` is thrown.
    private nonisolated static func render(
        sources: [URL],
        to destination: URL,
        maxPageDimension: Int,
        onPageRendered: (@Sendable (Int) -> Void)?
    ) throws {
        let cap = max(1, maxPageDimension)
        // The renderer needs a non-empty default bounds; every page overrides it with its own.
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: cap, height: cap),
            format: UIGraphicsPDFRendererFormat()
        )

        var pagesWritten = 0
        var wasCancelled = false

        do {
            try renderer.writePDF(to: destination) { context in
                for (index, source) in sources.enumerated() {
                    if Task.isCancelled { wasCancelled = true; break }
                    autoreleasepool {
                        guard let image = downscaledImage(from: source, maxPixel: cap) else {
                            return // unreadable — skip without a page
                        }
                        let bounds = CGRect(origin: .zero, size: image.size)
                        context.beginPage(withBounds: bounds, pageInfo: [:])
                        image.draw(in: bounds)
                        pagesWritten += 1
                        onPageRendered?(index)
                    }
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw PDFBuilderError.renderingFailed(destination)
        }

        if wasCancelled {
            try? FileManager.default.removeItem(at: destination)
            throw PDFBuilderError.cancelled
        }
        guard pagesWritten > 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw PDFBuilderError.noReadableImages
        }
    }

    /// Loads a source image downsampled so its longest edge is at most `maxPixel`, with the
    /// EXIF orientation baked in so the page is upright. ImageIO downsamples *as it decodes*, so
    /// the full-resolution bitmap is never materialized; a source already within the bound is
    /// returned at native size (never upscaled). Returns `nil` for anything that isn't a
    /// decodable image. The returned `UIImage` has scale 1, so its `size` equals the page's pixel
    /// dimensions in points.
    private nonisolated static func downscaledImage(from source: URL, maxPixel: Int) -> UIImage? {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0 else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            imageSource, 0, options as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
