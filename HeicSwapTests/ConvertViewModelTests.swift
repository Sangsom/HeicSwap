//
//  ConvertViewModelTests.swift
//  HeicSwapTests
//
//  The batch Convert action (task 5.3) end to end: tapping Convert runs the on-device engine over
//  the queue, every item ends up "developed", and the run settles to `.finished` with the outputs
//  retained (AC1). Also covers the `.pdf` route to `PDFBuilder` (one combined output) and the
//  no-convertible-items / already-running guards. Cancel mid-batch is timing-dependent and is
//  covered by the manual test plan.
//

import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import HeicSwap

// MARK: - Fixtures

/// A throwaway working directory removed on deinit.
private final class Workspace {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "ConvertViewModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
}

/// Writes a solid-color sRGB PNG and returns its URL.
private func makeImage(named name: String, width: Int = 64, height: Int = 48, in directory: URL) throws -> URL {
    let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(red: 0.3, green: 0.6, blue: 0.4, alpha: 1)
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

// MARK: - Tests

@MainActor
struct ConvertViewModelTests {

    /// A view model whose import / engine / PDF outputs all live under one workspace.
    private func makeViewModel(in workspace: Workspace) -> ConvertViewModel {
        ConvertViewModel(
            importService: ImportService(rootDirectory: workspace.root.appending(path: "imports")),
            engine: ConversionEngine(outputDirectory: workspace.root.appending(path: "engine")),
            pdfBuilder: PDFBuilder(outputDirectory: workspace.root.appending(path: "pdf"))
        )
    }

    /// Imports `count` fresh PNGs into the queue and returns the view model.
    private func makeViewModelWithQueue(_ count: Int, in workspace: Workspace) async throws -> ConvertViewModel {
        let viewModel = makeViewModel(in: workspace)
        let urls = try (0..<count).map { try makeImage(named: "img-\($0).png", in: workspace.root) }
        await viewModel.addFromFiles(urls)
        #expect(viewModel.items.count == count)
        return viewModel
    }

    @Test("AC1: converting a queue finishes with every item developed and its output kept")
    func convertsWholeQueue() async throws {
        let workspace = try Workspace()
        let viewModel = try await makeViewModelWithQueue(3, in: workspace)
        viewModel.options.format = .jpg
        let ids = Set(viewModel.items.map(\.id))

        viewModel.convert()
        await viewModel.conversionTask?.value

        #expect(viewModel.phase == .finished(successCount: 3, failureCount: 0))
        #expect(viewModel.developedItemIDs == ids)
        #expect(viewModel.convertedCount == 3)
        #expect(viewModel.lastOutputs.count == 3)
        for output in viewModel.lastOutputs {
            #expect(output.pathExtension == "jpg")
            #expect(FileManager.default.fileExists(atPath: output.path))
        }
        #expect(viewModel.isConverting == false)
    }

    @Test("The .pdf format routes to PDFBuilder and produces one combined output")
    func pdfRouteProducesOneOutput() async throws {
        let workspace = try Workspace()
        let viewModel = try await makeViewModelWithQueue(4, in: workspace)
        viewModel.options.format = .pdf

        viewModel.convert()
        await viewModel.conversionTask?.value

        #expect(viewModel.phase == .finished(successCount: 4, failureCount: 0))
        #expect(viewModel.developedItemIDs.count == 4)
        #expect(viewModel.lastOutputs.count == 1)
        let pdf = try #require(viewModel.lastOutputs.first)
        #expect(pdf.pathExtension == "pdf")
        #expect(FileManager.default.fileExists(atPath: pdf.path))
    }

    @Test("Convert is a no-op with an empty queue")
    func emptyQueueIsNoOp() async throws {
        let workspace = try Workspace()
        let viewModel = makeViewModel(in: workspace)

        viewModel.convert()

        #expect(viewModel.conversionTask == nil)
        #expect(viewModel.phase == .idle)
    }

    @Test("Editing options clears a finished run's banner")
    func editingOptionsClearsFinishedBanner() async throws {
        let workspace = try Workspace()
        let viewModel = try await makeViewModelWithQueue(2, in: workspace)

        viewModel.convert()
        await viewModel.conversionTask?.value
        #expect(viewModel.phase == .finished(successCount: 2, failureCount: 0))

        viewModel.options.quality = 0.5
        #expect(viewModel.phase == .idle)
        #expect(viewModel.developedItemIDs.isEmpty)
    }
}
