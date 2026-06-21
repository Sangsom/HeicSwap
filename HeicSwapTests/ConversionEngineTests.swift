//
//  ConversionEngineTests.swift
//  HeicSwapTests
//
//  Covers the conversion backbone across its three task areas, grouped into nested suites so
//  the Test navigator reads as Transcode (3.1) / Resize & compress (3.2) / Metadata stripping
//  (3.3): valid + color-preserved output, batch progress, failure isolation; downscale and
//  target-size compression; and opt-in EXIF/GPS stripping. True memory-bound profiling over a
//  50+ item batch is the Instruments step in the manual test plan / task 10.3.
//

import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import HeicSwap

// MARK: - Shared fixtures

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

/// Image fixtures and on-disk inspectors shared by the conversion-engine suites. Exposed through a
/// protocol extension so each nested `@Suite` uses them as plain instance methods — keeping the
/// suites groupable in the navigator without duplicating fixtures or threading a helper object.
private protocol ConversionFixtures {}

private extension ConversionFixtures {

    /// Whether the test host can encode HEIC, so HEIC-output assertions can be skipped where the
    /// codec is unavailable rather than failing spuriously.
    var heicEncodingSupported: Bool {
        let types = CGImageDestinationCopyTypeIdentifiers() as NSArray
        return types.contains(UTType.heic.identifier)
    }

    /// Writes a solid-color sRGB image to disk in `format` and returns its URL.
    func makeSourceImage(
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
    func makeCorruptFile(in directory: URL) throws -> URL {
        let url = directory.appending(path: "corrupt-\(UUID().uuidString).heic")
        try Data("not an image".utf8).write(to: url)
        return url
    }

    /// Writes a high-frequency pseudo-random sRGB image — incompressible noise, so its JPEG
    /// size is dominated by quality (a solid color would compress to nothing and never exercise
    /// the target-size search). Deterministic via a fixed seed so byte sizes are reproducible.
    func makeNoisyImage(
        width: Int, height: Int, format: OutputFormat = .png, in directory: URL
    ) throws -> URL {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let bytesPerRow = width * 4
        let count = bytesPerRow * height

        let image: CGImage = try { () throws -> CGImage in
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 1)
            defer { buffer.deallocate() }
            let bytes = buffer.assumingMemoryBound(to: UInt8.self)
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            for index in 0..<count {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                bytes[index] = UInt8(truncatingIfNeeded: seed)
            }
            let context = try #require(CGContext(
                data: buffer, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ))
            // makeImage() snapshots the bitmap, so the buffer is safe to free after this returns.
            return try #require(context.makeImage())
        }()

        let url = directory.appending(path: "noisy-\(UUID().uuidString).\(format.fileExtension)")
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, format.contentType.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary
        )
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// Writes a JPEG shaped like a real iPhone photo: a GPS dictionary, identifying Exif fields,
    /// and a TIFF block (camera make/model/software/timestamp + orientation), so strip behavior
    /// can be asserted against realistic embedded metadata rather than an empty baseline.
    func makeGeotaggedImage(
        width: Int = 64, height: Int = 48, in directory: URL
    ) throws -> URL {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 56.9496,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 24.1052,
            kCGImagePropertyGPSLongitudeRef: "E",
        ]
        let exif: [CFString: Any] = [
            kCGImagePropertyExifDateTimeOriginal: "2026:06:20 12:00:00",
            kCGImagePropertyExifUserComment: "HeicSwap geotag fixture",
        ]
        let tiff: [CFString: Any] = [
            kCGImagePropertyTIFFMake: "Apple",
            kCGImagePropertyTIFFModel: "iPhone 17 Pro",
            kCGImagePropertyTIFFSoftware: "26.5",
            kCGImagePropertyTIFFDateTime: "2026:06:20 12:00:00",
        ]
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: gps,
            kCGImagePropertyExifDictionary: exif,
            kCGImagePropertyTIFFDictionary: tiff,
            kCGImageDestinationLossyCompressionQuality: 0.95,
        ]

        let url = directory.appending(path: "geo-\(UUID().uuidString).jpg")
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// The on-disk byte size of a file.
    func fileSize(of url: URL) throws -> Int {
        try #require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }

    /// Pixel dimensions of an image on disk, read without fully decoding it.
    func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    /// The decoded color space name of an image on disk — the basis for the preservation check.
    func colorSpaceName(of url: URL) -> CFString? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return image.colorSpace?.name
    }

    /// Top-level ImageIO properties of an image on disk (the dict `CGImageSourceCopyPropertiesAtIndex`
    /// returns — where the `Exif`/`GPS`/`TIFF` sub-dictionaries live).
    func properties(of url: URL) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        return props
    }

    /// Asserts a converted output carries no location or identifying metadata. GPS is removed
    /// entirely — the privacy core. ImageIO re-synthesizes a *structural* Exif block for JPEG
    /// (`PixelXDimension`/`PixelYDimension`/`ColorSpace`) and keeps the TIFF `Orientation` tag so
    /// the image still displays correctly; those are derivable from the pixels and carry nothing
    /// private. What must never survive is the source's camera/timestamp/comment data, so this
    /// asserts each identifying field is gone.
    func expectNoIdentifyingMetadata(in props: [CFString: Any]) {
        #expect(props[kCGImagePropertyGPSDictionary] == nil)   // no location

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] == nil)
        #expect(exif[kCGImagePropertyExifUserComment] == nil)

        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        #expect(tiff[kCGImagePropertyTIFFMake] == nil)         // no camera make/model
        #expect(tiff[kCGImagePropertyTIFFModel] == nil)
        #expect(tiff[kCGImagePropertyTIFFSoftware] == nil)
        #expect(tiff[kCGImagePropertyTIFFDateTime] == nil)     // no capture timestamp
    }
}

// MARK: - Suite

struct ConversionEngineTests {

    // MARK: 3.1 — Transcode, batch, isolation

    @Suite("Transcode (3.1)")
    struct Transcode: ConversionFixtures {

        // AC1 — valid, color-preserved output

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
            try #require(heicEncodingSupported, "HEIC encoding unavailable in this test host")
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

        // AC2 — batch progress

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

        // AC3 — failure isolation

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

        // Output naming

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

    // MARK: 3.2 — Resize & compress

    @Suite("Resize & compress (3.2)")
    struct ResizeAndCompress: ConversionFixtures {

        // Resize (maxDimension)

        @Test("maxDimension 2048: longest side ≤ 2048 and aspect ratio preserved")
        func maxDimensionDownscalesAndPreservesAspect() async throws {
            let workspace = try Workspace()
            let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))
            // 3000×2000 (3:2) is larger than 2048 on its long edge, so it must downscale.
            let source = try makeSourceImage(width: 3000, height: 2000, format: .png, in: workspace.root)

            let output = try await engine.convert(
                source, with: ConversionOptions(format: .jpg, resizeMode: .maxDimension(pixels: 2048))
            )

            let size = try #require(pixelSize(of: output))
            #expect(max(size.width, size.height) <= 2048)
            #expect(size.width == 2048 && size.height == 1365) // 3:2 within rounding (2000·2048/3000)
            // Aspect ratio preserved to within a pixel of rounding.
            let sourceRatio = 3000.0 / 2000.0
            let outputRatio = Double(size.width) / Double(size.height)
            #expect(abs(sourceRatio - outputRatio) < 0.01)
        }

        @Test("maxDimension never upscales a source already within the limit")
        func maxDimensionDoesNotUpscale() async throws {
            let workspace = try Workspace()
            let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))
            let source = try makeSourceImage(width: 64, height: 48, format: .png, in: workspace.root)

            let output = try await engine.convert(
                source, with: ConversionOptions(format: .png, resizeMode: .maxDimension(pixels: 2048))
            )

            let size = try #require(pixelSize(of: output))
            #expect(size.width == 64 && size.height == 48)
        }

        @Test("A large photo resizes to the limit (downsample-on-load path)")
        func resizesLargePhoto() async throws {
            // Proves the downscale path drives a large source down to the limit. True peak-memory
            // bounding (AC3) is the Instruments step in the manual test plan / task 10.3.
            let workspace = try Workspace()
            let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))
            let source = try makeSourceImage(width: 4000, height: 3000, format: .jpg, in: workspace.root)

            let output = try await engine.convert(
                source, with: ConversionOptions(format: .jpg, resizeMode: .maxDimension(pixels: 1024))
            )

            let size = try #require(pixelSize(of: output))
            #expect(max(size.width, size.height) == 1024)
            #expect(size.width == 1024 && size.height == 768)
        }

        // Compress (targetBytes)

        @Test("targetBytes: output lands at/under the target and its size is reported")
        func targetBytesLandsUnderTarget() async throws {
            let workspace = try Workspace()
            let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))
            let source = try makeNoisyImage(width: 1500, height: 1000, format: .png, in: workspace.root)

            // Baseline: full-quality JPEG size, so we pick a target that genuinely forces the search
            // (comfortably below full quality, but well above the q=0 floor for noise).
            let fullQuality = try await engine.convert(source, with: ConversionOptions(format: .jpg, quality: 1.0))
            let fullSize = try fileSize(of: fullQuality)
            let target = max(150_000, fullSize / 4)

            let output = try await engine.convert(
                source, with: ConversionOptions(format: .jpg, resizeMode: .targetBytes(target))
            )

            let outputSize = try fileSize(of: output)
            #expect(outputSize <= target)            // AC2: at/under target
            #expect(outputSize > 0)                  // a real image was produced
            #expect(outputSize < fullSize)           // compression actually happened
            // Output is a valid JPEG at the original dimensions (targetBytes adjusts quality, not size).
            let imageSource = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
            #expect(UTType(CGImageSourceGetType(imageSource)! as String) == .jpeg)
            let size = try #require(pixelSize(of: output))
            #expect(size.width == 1500 && size.height == 1000)
        }

        @Test("targetBytes keeps full quality untouched when it already fits")
        func targetBytesKeepsFullQualityWhenItFits() async throws {
            let workspace = try Workspace()
            let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))
            let source = try makeNoisyImage(width: 800, height: 600, format: .png, in: workspace.root)

            let fullQuality = try await engine.convert(source, with: ConversionOptions(format: .jpg, quality: 1.0))
            let fullSize = try fileSize(of: fullQuality)

            // Target far above full quality → fast path keeps the full-quality encode byte-for-byte.
            let output = try await engine.convert(
                source, with: ConversionOptions(format: .jpg, resizeMode: .targetBytes(fullSize * 4))
            )

            #expect(try fileSize(of: output) == fullSize)
        }

        @Test("targetBytes on a lossless format falls back to a faithful encode")
        func targetBytesOnLosslessFormatFallsBack() async throws {
            // PNG size can't be driven by quality, so the engine emits one faithful copy rather than
            // failing or looping. The output may exceed the target — documented best-effort behavior.
            let workspace = try Workspace()
            let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))
            let source = try makeSourceImage(width: 200, height: 150, format: .jpg, in: workspace.root)

            let output = try await engine.convert(
                source, with: ConversionOptions(format: .png, resizeMode: .targetBytes(1_000))
            )

            #expect(output.pathExtension == "png")
            let imageSource = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
            #expect(UTType(CGImageSourceGetType(imageSource)! as String) == .png)
            let size = try #require(pixelSize(of: output))
            #expect(size.width == 200 && size.height == 150)
        }
    }

    // MARK: 3.3 — Metadata stripping

    @Suite("Metadata stripping (3.3)")
    struct MetadataStripping: ConversionFixtures {

        @Test("AC2: strip OFF (default) preserves the source GPS, Exif, and TIFF metadata")
        func stripOffPreservesMetadata() async throws {
            let workspace = try Workspace()
            let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))
            let source = try makeGeotaggedImage(in: workspace.root)

            // Sanity: the fixture really is geotagged before we convert it.
            let sourceProps = try #require(properties(of: source))
            #expect(sourceProps[kCGImagePropertyGPSDictionary] != nil)

            let output = try await engine.convert(
                source, with: ConversionOptions(format: .jpg, stripsMetadata: false)
            )

            let props = try #require(properties(of: output))
            let gps = try #require(props[kCGImagePropertyGPSDictionary] as? [CFString: Any])
            #expect(gps[kCGImagePropertyGPSLatitude] != nil)            // location survives
            let exif = try #require(props[kCGImagePropertyExifDictionary] as? [CFString: Any])
            #expect(exif[kCGImagePropertyExifDateTimeOriginal] != nil)  // Exif survives
            let tiff = try #require(props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
            #expect(tiff[kCGImagePropertyTIFFModel] != nil)             // camera info survives
        }

        @Test("AC1: strip ON removes GPS, Exif, and camera metadata from the converted output")
        func stripOnRemovesGpsAndExif() async throws {
            let workspace = try Workspace()
            let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))
            let source = try makeGeotaggedImage(in: workspace.root)

            let output = try await engine.convert(
                source, with: ConversionOptions(format: .jpg, stripsMetadata: true)
            )

            let props = try #require(properties(of: output))
            expectNoIdentifyingMetadata(in: props)
            // The image itself is intact: a valid JPEG at the original dimensions.
            let imageSource = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
            #expect(UTType(CGImageSourceGetType(imageSource)! as String) == .jpeg)
            let size = try #require(pixelSize(of: output))
            #expect(size.width == 64 && size.height == 48)
        }

        @Test("AC1: strip ON also clears metadata on the target-size compression path")
        func stripOnRemovesMetadataUnderTargetBytes() async throws {
            let workspace = try Workspace()
            let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))
            let source = try makeGeotaggedImage(width: 1200, height: 900, in: workspace.root)

            let output = try await engine.convert(
                source,
                with: ConversionOptions(
                    format: .jpg, resizeMode: .targetBytes(50_000), stripsMetadata: true
                )
            )

            let props = try #require(properties(of: output))
            expectNoIdentifyingMetadata(in: props)
        }

        @Test("AC1: strip ON keeps the downscaled output free of GPS/Exif")
        func stripOnRemovesMetadataUnderMaxDimension() async throws {
            let workspace = try Workspace()
            let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))
            let source = try makeGeotaggedImage(width: 1200, height: 900, in: workspace.root)

            let output = try await engine.convert(
                source,
                with: ConversionOptions(
                    format: .jpg, resizeMode: .maxDimension(pixels: 512), stripsMetadata: true
                )
            )

            let props = try #require(properties(of: output))
            expectNoIdentifyingMetadata(in: props)
        }
    }
}
