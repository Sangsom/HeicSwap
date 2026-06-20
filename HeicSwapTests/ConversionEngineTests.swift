//
//  ConversionEngineTests.swift
//  HeicSwapTests
//
//  Covers the conversion backbone (task 3.1): valid + color-preserved output across
//  formats (AC1), per-item progress over a batch (AC2), and failure isolation when one
//  item is corrupt (AC3). True memory-bound profiling over a 50+ item batch is the
//  Instruments step in the manual test plan / task 10.3.
//

import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import HeicSwap

struct ConversionEngineTests {

    // MARK: Fixtures

    /// A throwaway working directory for one test's inputs and outputs, removed on deinit.
    private final class Workspace {
        let root: URL
        init() throws {
            root = FileManager.default.temporaryDirectory
                .appending(path: "ConversionEngineTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: root) }
    }

    /// Whether the test host can encode HEIC, so HEIC-output assertions can be skipped where
    /// the codec is unavailable rather than failing spuriously.
    private static let heicEncodingSupported: Bool = {
        let types = CGImageDestinationCopyTypeIdentifiers() as NSArray
        return types.contains(UTType.heic.identifier)
    }()

    /// Writes a solid-color sRGB image to disk in `format` and returns its URL.
    private func makeSourceImage(
        width: Int = 64, height: Int = 48, format: OutputFormat = .png, in directory: URL
    ) throws -> URL {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let url = directory.appending(path: "src-\(UUID().uuidString).\(format.fileExtension)")
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, format.contentType.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary
        )
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// Writes bytes that are not a decodable image, under an image extension.
    private func makeCorruptFile(in directory: URL) throws -> URL {
        let url = directory.appending(path: "corrupt-\(UUID().uuidString).heic")
        try Data("not an image".utf8).write(to: url)
        return url
    }

    /// Pixel dimensions of an image on disk, read without fully decoding it.
    private func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    /// The decoded color space name of an image on disk — the basis for the preservation check.
    private func colorSpaceName(of url: URL) -> CFString? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return image.colorSpace?.name
    }

    // MARK: AC1 — valid, color-preserved output

    @Test("Converts PNG → JPEG: output is a valid JPEG with preserved dimensions and color")
    func convertsPngToJpeg() async throws {
        let workspace = try Workspace()
        let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))
        let source = try makeSourceImage(format: .png, in: workspace.root)

        let output = try await engine.convert(source, with: ConversionOptions(format: .jpg))

        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(output.pathExtension == "jpg")

        let imageSource = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(CGImageSourceGetCount(imageSource) == 1)
        #expect(UTType(CGImageSourceGetType(imageSource)! as String) == .jpeg)

        let size = try #require(pixelSize(of: output))
        #expect(size.width == 64 && size.height == 48)

        // Color profile preserved: the round-tripped image decodes to the same sRGB space.
        let sourceSpace = try #require(colorSpaceName(of: source))
        #expect(colorSpaceName(of: output) == sourceSpace)
    }

    @Test("Converts JPEG → PNG: output is a valid PNG with preserved dimensions")
    func convertsJpegToPng() async throws {
        let workspace = try Workspace()
        let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))
        let source = try makeSourceImage(format: .jpg, in: workspace.root)

        let output = try await engine.convert(source, with: ConversionOptions(format: .png))

        #expect(output.pathExtension == "png")
        let imageSource = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(UTType(CGImageSourceGetType(imageSource)! as String) == .png)
        let size = try #require(pixelSize(of: output))
        #expect(size.width == 64 && size.height == 48)
    }

    @Test("Converts PNG → HEIC where the codec is available")
    func convertsPngToHeic() async throws {
        try #require(Self.heicEncodingSupported, "HEIC encoding unavailable in this test host")
        let workspace = try Workspace()
        let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))
        let source = try makeSourceImage(format: .png, in: workspace.root)

        let output = try await engine.convert(source, with: ConversionOptions(format: .heic))

        #expect(output.pathExtension == "heic")
        let imageSource = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(UTType(CGImageSourceGetType(imageSource)! as String) == .heic)
        let size = try #require(pixelSize(of: output))
        #expect(size.width == 64 && size.height == 48)
    }

    @Test("PDF output is rejected — image→PDF is task 3.4, not the transcode path")
    func pdfOutputIsRejected() async throws {
        let workspace = try Workspace()
        let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))
        let source = try makeSourceImage(format: .png, in: workspace.root)

        await #expect(throws: ConversionError.unsupportedOutputFormat(.pdf)) {
            try await engine.convert(source, with: ConversionOptions(format: .pdf))
        }
    }

    // MARK: AC2 — batch progress

    @Test("Batch fires one progress callback per item and returns them in input order")
    func batchReportsPerItemProgress() async throws {
        let workspace = try Workspace()
        let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))
        let count = 12
        var sources: [URL] = []
        for _ in 0..<count { sources.append(try makeSourceImage(format: .png, in: workspace.root)) }

        // A Sendable, thread-safe collector for the @Sendable callback.
        actor Progress {
            private(set) var indices: [Int] = []
            func record(_ index: Int) { indices.append(index) }
        }
        let progress = Progress()

        let outcomes = await engine.convertBatch(
            sources, with: ConversionOptions(format: .jpg), maxConcurrent: 3
        ) { outcome in
            Task { await progress.record(outcome.index) }
        }

        #expect(outcomes.count == count)
        #expect(outcomes.allSatisfy { $0.didSucceed })
        #expect(outcomes.map(\.index) == Array(0..<count)) // returned in input order

        // Every item reported progress exactly once.
        let reported = await progress.indices.sorted()
        #expect(reported == Array(0..<count))
    }

    // MARK: AC3 — failure isolation

    @Test("One corrupt file fails in isolation; every other item still converts")
    func corruptItemIsIsolated() async throws {
        let workspace = try Workspace()
        let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))
        let good1 = try makeSourceImage(format: .png, in: workspace.root)
        let bad = try makeCorruptFile(in: workspace.root)
        let good2 = try makeSourceImage(format: .png, in: workspace.root)
        let good3 = try makeSourceImage(format: .png, in: workspace.root)

        let outcomes = await engine.convertBatch(
            [good1, bad, good2, good3], with: ConversionOptions(format: .jpg)
        )

        #expect(outcomes.count == 4)
        #expect(outcomes[0].didSucceed)
        #expect(outcomes[2].didSucceed)
        #expect(outcomes[3].didSucceed)

        // The corrupt item failed, and failed for the right reason.
        #expect(!outcomes[1].didSucceed)
        #expect(outcomes[1].result == .failure(.sourceUnreadable(bad)))

        // Successful outputs are on disk; the failed one produced none.
        #expect(outcomes[0].output.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        #expect(outcomes[1].output == nil)
    }

    @Test("Empty input returns no outcomes without error")
    func emptyBatch() async throws {
        let workspace = try Workspace()
        let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))
        let outcomes = await engine.convertBatch([], with: ConversionOptions())
        #expect(outcomes.isEmpty)
    }

    // MARK: Output naming

    @Test("Duplicate source base names get collision-free output names")
    func duplicateNamesDoNotCollide() async throws {
        let workspace = try Workspace()
        let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))
        // Same base name "photo", different extensions → both must produce distinct outputs.
        let png = workspace.root.appending(path: "photo.png")
        let jpg = workspace.root.appending(path: "photo.jpg")
        try FileManager.default.copyItem(at: try makeSourceImage(format: .png, in: workspace.root), to: png)
        try FileManager.default.copyItem(at: try makeSourceImage(format: .jpg, in: workspace.root), to: jpg)

        let outcomes = await engine.convertBatch([png, jpg], with: ConversionOptions(format: .png))

        let outputs = outcomes.compactMap(\.output)
        #expect(outputs.count == 2)
        #expect(Set(outputs.map(\.lastPathComponent)).count == 2) // distinct file names
        #expect(outputs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }
}
