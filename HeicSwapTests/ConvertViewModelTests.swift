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

import CoreGraphics
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

// MARK: - Spy

/// Records the analytics events the view model emits, so the value-gate hit (`pro_gate_hit`) can be
/// asserted without a real backend (task 6.3).
@MainActor
private final class SpyAnalyticsClient: AnalyticsClient {
    private(set) var events: [(name: String, parameters: [String: Any]?)] = []

    func logEvent(_ name: String, parameters: [String: Any]?) {
        events.append((name, parameters))
    }

    /// The `gate` parameter of the most recent `pro_gate_hit`, if any.
    var lastGateHit: String? {
        events.last { $0.name == "pro_gate_hit" }?.parameters?["gate"] as? String
    }

    var gateHitCount: Int { events.filter { $0.name == "pro_gate_hit" }.count }

    /// Parameters of the most recent event named `name`, if any (task 9.1).
    func lastParameters(of name: String) -> [String: Any]? {
        events.last { $0.name == name }?.parameters
    }

    func count(of name: String) -> Int { events.filter { $0.name == name }.count }
}

// MARK: - Tests

@MainActor
struct ConvertViewModelTests {

    /// A view model whose import / engine / PDF outputs all live under one workspace.
    private func makeViewModel(
        in workspace: Workspace,
        analytics: any AnalyticsClient = StubAnalyticsClient(),
        entitlement: Entitlement = .free
    ) -> ConvertViewModel {
        ConvertViewModel(
            importService: ImportService(rootDirectory: workspace.root.appending(path: "imports")),
            engine: ConversionEngine(outputDirectory: workspace.root.appending(path: "engine")),
            pdfBuilder: PDFBuilder(outputDirectory: workspace.root.appending(path: "pdf")),
            analytics: analytics,
            entitlement: entitlement
        )
    }

    /// Imports `count` fresh PNGs into the queue and returns the view model.
    private func makeViewModelWithQueue(
        _ count: Int,
        in workspace: Workspace,
        analytics: any AnalyticsClient = StubAnalyticsClient(),
        entitlement: Entitlement = .free
    ) async throws -> ConvertViewModel {
        let viewModel = makeViewModel(in: workspace, analytics: analytics, entitlement: entitlement)
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

    @Test("AC1 (5.4): each output carries its before/after size for the Results sheet")
    func resultsCarrySizes() async throws {
        let workspace = try Workspace()
        let viewModel = try await makeViewModelWithQueue(3, in: workspace)
        viewModel.options.format = .jpg

        viewModel.convert()
        await viewModel.conversionTask?.value

        #expect(viewModel.lastResults.count == 3)
        #expect(viewModel.lastResults.map(\.outputURL) == viewModel.lastOutputs)
        for result in viewModel.lastResults {
            #expect(result.originalBytes > 0)
            #expect(result.outputBytes > 0)
            #expect(result.isPDF == false)
        }
    }

    @Test("The .pdf result sums its inputs as the original size")
    func pdfResultSumsInputs() async throws {
        let workspace = try Workspace()
        let viewModel = try await makeViewModelWithQueue(4, in: workspace)
        viewModel.options.format = .pdf

        viewModel.convert()
        await viewModel.conversionTask?.value

        let result = try #require(viewModel.lastResults.first)
        #expect(viewModel.lastResults.count == 1)
        #expect(result.isPDF)
        #expect(result.outputBytes > 0)
        #expect(result.originalBytes > 0)
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

    // MARK: Reorder (task 5.5)

    @Test("AC1 (5.5): moving a page updates the queue order")
    func reorderUpdatesQueueOrder() async throws {
        let workspace = try Workspace()
        let viewModel = try await makeViewModelWithQueue(4, in: workspace)
        let original = viewModel.items.map(\.id)

        // Drag the first page to the end of the four-item queue.
        viewModel.moveItems(fromOffsets: IndexSet(integer: 0), toOffset: 4)

        #expect(viewModel.items.map(\.id) == [original[1], original[2], original[3], original[0]])
    }

    @Test("Reorder is offered only for a multi-page PDF target")
    func reorderAvailability() async throws {
        let workspace = try Workspace()
        let viewModel = try await makeViewModelWithQueue(3, in: workspace)

        viewModel.options.format = .jpg
        #expect(viewModel.canReorderForPDF == false)

        viewModel.options.format = .pdf
        #expect(viewModel.canReorderForPDF == true)
    }

    @Test("A single-page PDF has no order to arrange")
    func singlePagePDFIsNotReorderable() async throws {
        let workspace = try Workspace()
        let viewModel = try await makeViewModelWithQueue(1, in: workspace)
        viewModel.options.format = .pdf
        #expect(viewModel.canReorderForPDF == false)
    }

    @Test("AC2 (5.5): a reordered queue exports the PDF in the new page order")
    func reorderedQueueExportsPDFInNewOrder() async throws {
        let workspace = try Workspace()
        let viewModel = makeViewModel(in: workspace)

        // Three distinct aspect ratios so each page is identifiable by its shape alone. The images
        // are small (≤120px), so PDFBuilder doesn't downscale and each page's media box keeps the
        // source aspect ratio exactly.
        let wide = try makeImage(named: "wide.png", width: 120, height: 40, in: workspace.root)    // ≈ 3.0
        let tall = try makeImage(named: "tall.png", width: 40, height: 120, in: workspace.root)    // ≈ 0.33
        let square = try makeImage(named: "square.png", width: 80, height: 80, in: workspace.root) // ≈ 1.0
        await viewModel.addFromFiles([wide, tall, square])
        viewModel.options.format = .pdf

        // Move the first page (wide) to the end → [tall, square, wide].
        viewModel.moveItems(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        viewModel.convert()
        await viewModel.conversionTask?.value

        let pdfURL = try #require(viewModel.lastOutputs.first)
        let document = try #require(CGPDFDocument(pdfURL as CFURL))
        #expect(document.numberOfPages == 3)

        let aspects = try (1...document.numberOfPages).map { pageIndex -> CGFloat in
            let box = try #require(document.page(at: pageIndex)).getBoxRect(.mediaBox)
            return box.width / box.height
        }
        #expect(abs(aspects[0] - 0.333) < 0.05) // tall
        #expect(abs(aspects[1] - 1.0) < 0.05)   // square
        #expect(abs(aspects[2] - 3.0) < 0.1)    // wide
    }

    // MARK: Value gate → paywall (task 6.3)

    @Test("AC1: a free user converting over the free limit hits the paywall (batch_size) instead of converting")
    func gatedConvertPresentsPaywall() async throws {
        let workspace = try Workspace()
        let analytics = SpyAnalyticsClient()
        let viewModel = try await makeViewModelWithQueue(
            ValueGate.freeBatchLimit + 1, in: workspace, analytics: analytics, entitlement: .free
        )

        viewModel.convert()

        #expect(viewModel.paywallTrigger == .batchSize)
        #expect(viewModel.conversionTask == nil) // nothing ran
        #expect(viewModel.phase == .idle)
        #expect(analytics.lastGateHit == "batch_size")
    }

    @Test("AC2: purchasing from the gate resumes the blocked conversion on dismiss")
    func purchaseResumesConversion() async throws {
        let workspace = try Workspace()
        let count = ValueGate.freeBatchLimit + 1
        let viewModel = try await makeViewModelWithQueue(count, in: workspace, entitlement: .free)
        let ids = Set(viewModel.items.map(\.id))

        viewModel.convert()
        #expect(viewModel.paywallTrigger == .batchSize)

        // The view syncs the upgraded entitlement and clears the sheet binding before onDismiss.
        viewModel.entitlement = .pro
        viewModel.paywallTrigger = nil
        viewModel.paywallDismissed()

        await viewModel.conversionTask?.value
        #expect(viewModel.phase == .finished(successCount: count, failureCount: 0))
        #expect(viewModel.developedItemIDs == ids)
        #expect(viewModel.lastOutputs.count == count)
    }

    @Test("AC3: dismissing the gate without buying keeps the free tier and a within-limit run still converts")
    func dismissKeepsFreeTier() async throws {
        let workspace = try Workspace()
        let viewModel = try await makeViewModelWithQueue(
            ValueGate.freeBatchLimit + 1, in: workspace, entitlement: .free
        )

        viewModel.convert()
        #expect(viewModel.paywallTrigger == .batchSize)

        // Dismiss without buying — still free.
        viewModel.paywallTrigger = nil
        viewModel.paywallDismissed()
        #expect(viewModel.conversionTask == nil)
        #expect(viewModel.phase == .idle)

        // Drop back within the free limit and convert — no gate this time.
        let firstID = try #require(viewModel.items.first?.id)
        viewModel.remove(firstID)
        #expect(viewModel.items.count == ValueGate.freeBatchLimit)

        viewModel.convert()
        #expect(viewModel.paywallTrigger == nil)
        await viewModel.conversionTask?.value
        #expect(viewModel.phase == .finished(successCount: ValueGate.freeBatchLimit, failureCount: 0))
    }

    @Test("A Pro user converts a large batch without hitting the gate")
    func proUserSkipsGate() async throws {
        let workspace = try Workspace()
        let count = ValueGate.freeBatchLimit + 3
        let viewModel = try await makeViewModelWithQueue(count, in: workspace, entitlement: .pro)

        viewModel.convert()

        #expect(viewModel.paywallTrigger == nil)
        await viewModel.conversionTask?.value
        #expect(viewModel.phase == .finished(successCount: count, failureCount: 0))
    }

    @Test("An options gate stages the paywall until the Options sheet dismisses, then resumes on purchase", arguments: [
        ValueGate.Trigger.stripMetadata,
        ValueGate.Trigger.targetSize,
    ])
    func optionsGateStagesAndResumes(trigger: ValueGate.Trigger) async throws {
        let workspace = try Workspace()
        let analytics = SpyAnalyticsClient()
        let viewModel = try await makeViewModelWithQueue(2, in: workspace, analytics: analytics, entitlement: .free)

        // Tap a locked control in the Options sheet: logs the gate, stages (no paywall yet).
        viewModel.requestProForOption(trigger)
        #expect(analytics.lastGateHit == trigger.rawValue)
        #expect(viewModel.paywallTrigger == nil) // staged behind the still-open Options sheet

        // Options sheet dismisses → paywall presents.
        viewModel.presentStagedPaywall()
        #expect(viewModel.paywallTrigger == trigger)

        // Purchase → the originally-tapped option is applied on dismiss.
        viewModel.entitlement = .pro
        viewModel.paywallTrigger = nil
        viewModel.paywallDismissed()

        switch trigger {
        case .stripMetadata:
            #expect(viewModel.options.stripsMetadata)
        case .targetSize:
            #expect(viewModel.options.resizeMode == .targetBytes(ResizeOption.defaultBytes))
        case .batchSize:
            Issue.record("batch size is not an options gate")
        }
    }

    @Test("Dismissing an options gate without buying leaves options unchanged")
    func optionsGateDismissLeavesOptionsUnchanged() async throws {
        let workspace = try Workspace()
        let viewModel = try await makeViewModelWithQueue(2, in: workspace, entitlement: .free)
        let before = viewModel.options

        viewModel.requestProForOption(.stripMetadata)
        viewModel.presentStagedPaywall()

        // Dismiss without buying.
        viewModel.paywallTrigger = nil
        viewModel.paywallDismissed()

        #expect(viewModel.options == before)
        #expect(viewModel.options.stripsMetadata == false)
    }

    // MARK: Analytics events (task 9.1)

    @Test("images_imported fires with the added count and source; the Files path emits no icloud_download")
    func imagesImportedOnFileImport() async throws {
        let workspace = try Workspace()
        let analytics = SpyAnalyticsClient()
        let viewModel = makeViewModel(in: workspace, analytics: analytics)
        let urls = try (0..<3).map { try makeImage(named: "in-\($0).png", in: workspace.root) }

        await viewModel.addFromFiles(urls)

        let params = try #require(analytics.lastParameters(of: "images_imported"))
        #expect(params["count"] as? Int == 3)
        #expect(params["source"] as? String == "files")
        // The Files path is a local copy — no iCloud-original fetch signal (that's the Photos path).
        #expect(analytics.count(of: "icloud_download") == 0)
    }

    @Test("AC2/AC3: conversion_completed fires with counts/format/flags/duration and only the §7 keys")
    func conversionCompletedEmitsNonPIIParams() async throws {
        let workspace = try Workspace()
        let analytics = SpyAnalyticsClient()
        let viewModel = try await makeViewModelWithQueue(2, in: workspace, analytics: analytics)
        viewModel.options.format = .jpg

        viewModel.convert()
        await viewModel.conversionTask?.value
        #expect(viewModel.phase == .finished(successCount: 2, failureCount: 0))

        let params = try #require(analytics.lastParameters(of: "conversion_completed"))
        #expect(params["count_success"] as? Int == 2)
        #expect(params["count_failed"] as? Int == 0)
        #expect(params["target_format"] as? String == "jpg")
        #expect(params["is_batch"] as? Bool == true)   // two inputs
        #expect(params["to_pdf"] as? Bool == false)
        #expect(params["used_strip"] as? Bool == false)
        #expect(params["used_resize"] as? Bool == false)
        #expect(params["duration_ms"] as? Int != nil)
        // Exactly the §7 set — no file names or paths can ride along (AC3).
        #expect(Set(params.keys) == [
            "count_success", "count_failed", "target_format", "is_batch",
            "used_resize", "used_strip", "to_pdf", "duration_ms",
        ])
    }
}
