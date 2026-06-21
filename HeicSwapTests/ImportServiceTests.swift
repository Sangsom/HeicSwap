//
//  ImportServiceTests.swift
//  HeicSwapTests
//
//  Covers the import service (task 3.5) on the deterministic, unit-testable paths: the Files
//  import path proves order preservation (AC1) and unsupported-flagged-not-crashed (AC3), and
//  `FileImportLoader` is tested directly for its supported-image gate. The Photos path
//  (`PhotosPickerItem` / iCloud download) can't be constructed in a unit test — it's covered by
//  the manual test plan — but it shares the same validation and queueing code paths exercised here.
//

import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import HeicSwap

// MARK: - Fixtures

/// A throwaway working directory for one test's inputs and the service's output, removed on deinit.
private final class Workspace {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "ImportServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
}

/// Writes a solid-color sRGB PNG of the given pixel size under `name`, and returns its URL.
private func makeImage(named name: String, width: Int = 64, height: Int = 48, in directory: URL) throws -> URL {
    let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())

    let url = directory.appending(path: name)
    let destination = try #require(CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
}

/// Writes bytes that are not a decodable image, under an image-looking extension.
private func makeUnsupportedFile(named name: String, in directory: URL) throws -> URL {
    let url = directory.appending(path: name)
    try Data("this is not an image".utf8).write(to: url)
    return url
}

// MARK: - FileImportLoader

struct FileImportLoaderTests {

    @Test("AC3: a non-image file is rejected, not treated as importable")
    func rejectsNonImage() async throws {
        let workspace = try Workspace()
        let loader = FileImportLoader(
            rootDirectory: workspace.root.appending(path: "out"),
            supportedContentTypes: ImportService.supportedContentTypes
        )
        let bogus = try makeUnsupportedFile(named: "notes.jpg", in: workspace.root)

        #expect(!loader.isSupportedImage(at: bogus))
        await #expect(throws: ImportError.unsupportedType(name: "notes.jpg")) {
            _ = try await loader.importFile(at: bogus)
        }
    }

    @Test("A supported image is accepted and copied, preserving its file name")
    func copiesSupportedImage() async throws {
        let workspace = try Workspace()
        let loader = FileImportLoader(
            rootDirectory: workspace.root.appending(path: "out"),
            supportedContentTypes: ImportService.supportedContentTypes
        )
        let source = try makeImage(named: "photo.png", in: workspace.root)

        #expect(loader.isSupportedImage(at: source))
        let destination = try await loader.importFile(at: source)

        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(destination.lastPathComponent == "photo.png")
        #expect(destination.path != source.path) // copied, not referenced in place
    }
}

// MARK: - ImportService (Files path)

@MainActor
struct ImportServiceTests {

    private func makeService(in workspace: Workspace) -> ImportService {
        ImportService(rootDirectory: workspace.root.appending(path: "imports"))
    }

    @Test("AC1: importing N files enqueues N ready items in the order given")
    func filesEnqueueInOrder() async throws {
        let workspace = try Workspace()
        let service = makeService(in: workspace)
        let names = ["a.png", "b.png", "c.png", "d.png"]
        let urls = try names.map { try makeImage(named: $0, in: workspace.root) }

        await service.importFromFiles(urls)

        #expect(service.items.count == 4)
        #expect(service.skipped.isEmpty)
        let importedNames = service.items.map { url in
            if case let .file(fileURL) = url.source { return fileURL.lastPathComponent }
            return ""
        }
        #expect(importedNames == names)
    }

    @Test("AC3: an unsupported file among supported ones is skipped, the rest still enqueue")
    func unsupportedIsSkippedRestEnqueue() async throws {
        let workspace = try Workspace()
        let service = makeService(in: workspace)
        let good1 = try makeImage(named: "good1.png", in: workspace.root)
        let bad = try makeUnsupportedFile(named: "bad.jpg", in: workspace.root)
        let good2 = try makeImage(named: "good2.png", in: workspace.root)

        await service.importFromFiles([good1, bad, good2])

        #expect(service.items.count == 2)
        #expect(service.skipped.count == 1)
        #expect(service.skipped.first?.label == "bad.jpg")
        #expect(service.skipped.first?.reason == .unsupportedType(name: "bad.jpg"))
    }

    @Test("Items can be removed from the queue by id")
    func removesItem() async throws {
        let workspace = try Workspace()
        let service = makeService(in: workspace)
        let url = try makeImage(named: "one.png", in: workspace.root)

        await service.importFromFiles([url])
        let id = try #require(service.items.first?.id)
        service.remove(id)

        #expect(service.items.isEmpty)
    }
}
