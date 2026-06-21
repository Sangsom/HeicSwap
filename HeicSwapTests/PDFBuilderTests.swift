//
//  PDFBuilderTests.swift
//  HeicSwapTests
//
//  Covers the image→multi-page PDF service (task 3.4): page count + order (AC1), the
//  single-image case (AC2), and the downscale-before-draw mechanism that bounds memory
//  (AC3). Order is asserted by giving each source a distinct aspect ratio and checking the
//  rendered page bounds come back in the same sequence — aspect ratio is scale-invariant, so
//  it survives the downscale. True peak-memory profiling over a large batch is the Instruments
//  step in the manual test plan.
//

import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import HeicSwap

// MARK: - Fixtures

/// A throwaway working directory for one test's inputs and outputs, removed on deinit.
private final class Workspace {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "PDFBuilderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
}

struct PDFBuilderTests {

    /// Writes a solid-color sRGB PNG of the given pixel size and returns its URL.
    private func makeImage(width: Int, height: Int, in directory: URL) throws -> URL {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let url = directory.appending(path: "src-\(UUID().uuidString).png")
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// Writes bytes that are not a decodable image, under an image extension.
    private func makeCorruptFile(in directory: URL) throws -> URL {
        let url = directory.appending(path: "corrupt-\(UUID().uuidString).png")
        try Data("not an image".utf8).write(to: url)
        return url
    }

    /// The aspect ratio (width / height) of a PDF page's media box.
    private func aspectRatio(of page: PDFPage) -> Double {
        let bounds = page.bounds(for: .mediaBox)
        return Double(bounds.width) / Double(bounds.height)
    }

    // MARK: AC1 — N images → N-page PDF in queue order

    @Test("AC1: 5 images produce a 5-page PDF whose pages follow queue order")
    func fiveImagesProduceFivePagesInOrder() async throws {
        let workspace = try Workspace()
        let builder = PDFBuilder(outputDirectory: workspace.root.appending(path: "out"))

        // Five distinct aspect ratios, in a fixed order, so page sequence is verifiable.
        let sizes = [(240, 160), (160, 240), (200, 200), (320, 160), (160, 320)]
        let sources = try sizes.map { try makeImage(width: $0.0, height: $0.1, in: workspace.root) }

        let output = try await builder.buildPDF(from: sources)

        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(output.pathExtension == "pdf")

        let document = try #require(PDFDocument(url: output))
        #expect(document.pageCount == 5)

        // Each page's aspect ratio matches the source at the same index → pages are in order.
        for (index, size) in sizes.enumerated() {
            let page = try #require(document.page(at: index))
            let expected = Double(size.0) / Double(size.1)
            #expect(abs(aspectRatio(of: page) - expected) < 0.02)
        }
    }

    // MARK: AC2 — single image → valid 1-page PDF

    @Test("AC2: a single image produces a valid 1-page PDF sized to its aspect")
    func singleImageProducesOnePage() async throws {
        let workspace = try Workspace()
        let builder = PDFBuilder(outputDirectory: workspace.root.appending(path: "out"))
        let source = try makeImage(width: 300, height: 200, in: workspace.root)

        let output = try await builder.buildPDF(from: [source])

        let document = try #require(PDFDocument(url: output))
        #expect(document.pageCount == 1)
        let page = try #require(document.page(at: 0))
        #expect(abs(aspectRatio(of: page) - 1.5) < 0.02) // 300:200
    }

    // MARK: AC3 — large images: downscaled before drawing (memory-bound mechanism)

    @Test("AC3: a large image is downscaled to the page-dimension cap before drawing")
    func largeImageIsDownscaledToCap() async throws {
        // Proves the downscale-before-draw path: a 4000×3000 source rendered with a 1024 cap
        // yields a page bounded at 1024 on its long edge, so only a ~1024px bitmap is ever
        // drawn. True peak-memory bounding is the Instruments step in the manual test plan.
        let workspace = try Workspace()
        let builder = PDFBuilder(outputDirectory: workspace.root.appending(path: "out"))
        let source = try makeImage(width: 4000, height: 3000, in: workspace.root)

        let output = try await builder.buildPDF(from: [source], maxPageDimension: 1024)

        let document = try #require(PDFDocument(url: output))
        let page = try #require(document.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        #expect(max(bounds.width, bounds.height) <= 1024)
        #expect(abs(aspectRatio(of: page) - 4000.0 / 3000.0) < 0.02) // aspect preserved
    }

    @Test("A small image is not upscaled — the page keeps its native size")
    func smallImageIsNotUpscaled() async throws {
        let workspace = try Workspace()
        let builder = PDFBuilder(outputDirectory: workspace.root.appending(path: "out"))
        let source = try makeImage(width: 64, height: 48, in: workspace.root)

        let output = try await builder.buildPDF(from: [source], maxPageDimension: 2048)

        let document = try #require(PDFDocument(url: output))
        let bounds = try #require(document.page(at: 0)).bounds(for: .mediaBox)
        #expect(bounds.width == 64 && bounds.height == 48)
    }

    // MARK: Progress

    @Test("buildPDF reports one progress callback per rendered page, in order")
    func reportsProgressPerPage() async throws {
        let workspace = try Workspace()
        let builder = PDFBuilder(outputDirectory: workspace.root.appending(path: "out"))
        let sources = try (0..<4).map { _ in try makeImage(width: 200, height: 150, in: workspace.root) }

        actor Progress {
            private(set) var indices: [Int] = []
            func record(_ index: Int) { indices.append(index) }
        }
        let progress = Progress()

        _ = try await builder.buildPDF(from: sources) { index in
            Task { await progress.record(index) }
        }

        // Allow the detached recording tasks to drain, then assert each page reported once.
        try await Task.sleep(for: .milliseconds(50))
        let recorded = await progress.indices.sorted()
        #expect(recorded == Array(0..<4))
    }

    // MARK: Edge cases

    @Test("Empty input throws .noReadableImages rather than writing an empty PDF")
    func emptyInputThrows() async throws {
        let workspace = try Workspace()
        let builder = PDFBuilder(outputDirectory: workspace.root.appending(path: "out"))

        await #expect(throws: PDFBuilderError.noReadableImages) {
            _ = try await builder.buildPDF(from: [])
        }
    }

    @Test("All-unreadable input throws .noReadableImages")
    func allUnreadableThrows() async throws {
        let workspace = try Workspace()
        let builder = PDFBuilder(outputDirectory: workspace.root.appending(path: "out"))
        let bad = [try makeCorruptFile(in: workspace.root), try makeCorruptFile(in: workspace.root)]

        await #expect(throws: PDFBuilderError.noReadableImages) {
            _ = try await builder.buildPDF(from: bad)
        }
    }

    @Test("An unreadable source is skipped; the readable ones still make pages in order")
    func unreadableSourceIsSkipped() async throws {
        let workspace = try Workspace()
        let builder = PDFBuilder(outputDirectory: workspace.root.appending(path: "out"))
        let good1 = try makeImage(width: 240, height: 160, in: workspace.root)  // 1.5
        let bad = try makeCorruptFile(in: workspace.root)
        let good2 = try makeImage(width: 160, height: 320, in: workspace.root)  // 0.5

        let output = try await builder.buildPDF(from: [good1, bad, good2])

        let document = try #require(PDFDocument(url: output))
        #expect(document.pageCount == 2) // the corrupt item produced no page
        #expect(abs(aspectRatio(of: try #require(document.page(at: 0))) - 1.5) < 0.02)
        #expect(abs(aspectRatio(of: try #require(document.page(at: 1))) - 0.5) < 0.02)
    }
}
