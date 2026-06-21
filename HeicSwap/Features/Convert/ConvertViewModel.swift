//
//  ConvertViewModel.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 21/06/2026.
//

import PhotosUI
import SwiftUI
import UIKit

/// Where the batch Convert action (task 5.3) is in its lifecycle. `idle` before a run and after a
/// cancel; `converting` while the engine works; `finished` once a run completes naturally (the
/// counts back the completion banner). Equatable so the view can switch on it.
enum ConversionPhase: Equatable {
    case idle
    case converting
    case finished(successCount: Int, failureCount: Int)
}

/// State owner for the Convert screen: the queue of images (task 5.1), the conversion options the
/// sheet edits (task 5.2), and the batch Convert action with its "developing" reveal (task 5.3).
///
/// Wraps `ImportService` and re-exposes its observable queue so the view binds to one object, and
/// drives the on-device `ConversionEngine` / `PDFBuilder`, surfacing per-item completion so each
/// thumbnail can develop as it finishes.
@MainActor
@Observable
final class ConvertViewModel {

    private let importService: ImportService
    private let engine: ConversionEngine
    private let pdfBuilder: PDFBuilder

    /// The conversion settings the Options sheet (task 5.2) edits and the Convert action (5.3)
    /// reads. Held here — not in the sheet — so choices persist as session defaults across
    /// presentations. Editing options clears a stale completion banner.
    var options = ConversionOptions() {
        didSet { clearFinishedState() }
    }

    /// The user's current entitlement, which gates the advanced options in the sheet (PRD §6).
    /// Stubbed `.free`; the entitlement client (task 6.1) will drive this from `PurchaseClient`.
    var entitlement: Entitlement

    /// The batch Convert lifecycle (task 5.3).
    private(set) var phase: ConversionPhase = .idle

    /// Ids of items that have finished converting this run — drives the per-item "develop" reveal.
    /// Reset at the start of each run; only consulted while `phase == .converting`.
    private(set) var developedItemIDs: Set<SourceItem.ID> = []

    /// Outputs produced by the most recent run — each with its before/after size — kept for the
    /// Results sheet (task 5.4) and so a cancelled run's already-converted outputs are retained
    /// ("converted ones kept", AC3 of 5.3).
    private(set) var lastResults: [ConversionResult] = []

    /// The output file URLs of the most recent run, in order. Derived from `lastResults`.
    var lastOutputs: [URL] { lastResults.map(\.outputURL) }

    /// Number of items the in-flight run is converting — the progress-bar denominator.
    private(set) var conversionTotal = 0

    /// The in-flight conversion, retained so a second tap can't start a parallel run, `cancel()`
    /// can stop it, and tests can await it.
    private(set) var conversionTask: Task<Void, Never>?

    init(
        importService: ImportService = ImportService(),
        engine: ConversionEngine = ConversionEngine(),
        pdfBuilder: PDFBuilder = PDFBuilder(),
        entitlement: Entitlement = .free
    ) {
        self.importService = importService
        self.engine = engine
        self.pdfBuilder = pdfBuilder
        self.entitlement = entitlement
    }

    /// Materialized items ready to convert, in import order.
    var items: [SourceItem] { importService.items }

    /// Imports still downloading (the Photos / iCloud-optimized case) or failed mid-download.
    var activeImports: [ActiveImport] { importService.active }

    /// Inputs flagged and skipped because they aren't usable images.
    var skipped: [ImportSkip] { importService.skipped }

    /// True when there's nothing to show — no ready items and nothing downloading. Drives the
    /// empty state. (Skips alone don't count: an all-skipped import should fall back to empty.)
    var isEmpty: Bool {
        items.isEmpty && activeImports.isEmpty
    }

    /// Whether a batch conversion is currently running.
    var isConverting: Bool {
        phase == .converting
    }

    /// Items finished so far in the in-flight (or just-completed) run — the progress-bar numerator.
    var convertedCount: Int { developedItemIDs.count }

    // MARK: Add

    /// Imports the picked Photos items (downloading iCloud originals on demand), appending them
    /// to the queue in selection order.
    func addFromPhotos(_ selection: [PhotosPickerItem]) async {
        clearFinishedState()
        await importService.importFromPhotos(selection)
    }

    /// Imports the chosen image files, appending them to the queue in order.
    func addFromFiles(_ urls: [URL]) async {
        clearFinishedState()
        await importService.importFromFiles(urls)
    }

    // MARK: Remove

    /// Removes a single queued item (or a failed/skipped row) by id; the rest are untouched.
    func remove(_ id: SourceItem.ID) {
        clearFinishedState()
        importService.remove(id)
    }

    /// Empties the entire queue.
    func clearAll() {
        importService.removeAll()
        phase = .idle
        developedItemIDs = []
        lastResults = []
    }

    /// Dismisses the skipped-items note.
    func clearSkipped() {
        importService.clearSkipped()
    }

    // MARK: Convert (task 5.3)

    /// Runs the on-device engine over the current queue, surfacing each item's completion so its
    /// thumbnail can "develop". Image formats go through `ConversionEngine` (N→N transcode);
    /// `.pdf` goes through `PDFBuilder` (N→1 assembly). A no-op if a run is already in flight or
    /// the queue has nothing convertible.
    func convert() {
        guard !isConverting else { return }

        // Pair each file-backed item with its id, preserving order, so the engine's per-item index
        // maps back to the right thumbnail. (Every imported item materializes to a file today; the
        // `.photoLibraryAsset` case is a placeholder and is simply skipped here.)
        let convertible: [(id: SourceItem.ID, url: URL)] = items.compactMap { item in
            guard case let .file(url) = item.source else { return nil }
            return (item.id, url)
        }
        guard !convertible.isEmpty else { return }

        let ids = convertible.map(\.id)
        let urls = convertible.map(\.url)
        let options = self.options

        developedItemIDs = []
        lastResults = []
        conversionTotal = urls.count
        phase = .converting

        conversionTask = Task { [weak self] in
            guard let self else { return }
            if options.format == .pdf {
                await self.runPDFBuild(ids: ids, urls: urls)
            } else {
                await self.runBatchConvert(ids: ids, urls: urls, options: options)
            }
            self.conversionTask = nil
        }
    }

    /// Stops the in-flight run. Items already converted (or in flight) keep their outputs; not-yet-
    /// started items are abandoned (AC3). The run settles back to `.idle`.
    func cancelConversion() {
        conversionTask?.cancel()
    }

    // MARK: Run drivers

    /// Drives `ConversionEngine.convertBatch`, bridging its off-actor per-item callback onto the
    /// main actor through an `AsyncStream` so completions are observed in order without nested
    /// `Task` hops. The producer runs as a structured child (`async let`), so cancelling the
    /// owning task propagates straight into the engine's task group.
    private func runBatchConvert(
        ids: [SourceItem.ID], urls: [URL], options: ConversionOptions
    ) async {
        let engine = self.engine
        let (stream, continuation) = AsyncStream<ConversionOutcome>.makeStream()

        async let production: Void = {
            await engine.convertBatch(urls, with: options) { outcome in
                continuation.yield(outcome)
            }
            continuation.finish()
        }()

        var successCount = 0
        var failureCount = 0
        for await outcome in stream {
            switch outcome.result {
            case let .success(output):
                successCount += 1
                lastResults.append(ConversionResult(
                    outputURL: output,
                    originalBytes: Self.byteCount(of: outcome.source),
                    outputBytes: Self.byteCount(of: output)
                ))
                develop(ids, at: outcome.index)
            case .failure(.cancelled):
                break // stopped, not finished — leaves the thumbnail undeveloped
            case .failure:
                failureCount += 1
                develop(ids, at: outcome.index)
            }
        }
        await production

        settle(successCount: successCount, failureCount: failureCount)
    }

    /// Drives `PDFBuilder.buildPDF`, revealing each thumbnail as its page renders. The whole PDF is
    /// one output; a cancelled or all-unreadable build produces none.
    private func runPDFBuild(ids: [SourceItem.ID], urls: [URL]) async {
        let pdfBuilder = self.pdfBuilder
        let (stream, continuation) = AsyncStream<Int>.makeStream()

        async let production: URL? = {
            defer { continuation.finish() }
            return try? await pdfBuilder.buildPDF(from: urls) { pageIndex in
                continuation.yield(pageIndex)
            }
        }()

        for await pageIndex in stream {
            develop(ids, at: pageIndex)
        }
        let output = await production

        if let output {
            // One combined PDF; its "before" is the sum of every input it was assembled from.
            let originalBytes = urls.reduce(0) { $0 + Self.byteCount(of: $1) }
            lastResults = [ConversionResult(
                outputURL: output,
                originalBytes: originalBytes,
                outputBytes: Self.byteCount(of: output)
            )]
        }
        let rendered = developedItemIDs.count
        settle(successCount: rendered, failureCount: urls.count - rendered)
    }

    /// File size in bytes for `url`, or `0` if it can't be read. A single `stat`-class call —
    /// cheap enough to run inline as each output lands, so the Results sheet has before/after sizes.
    private nonisolated static func byteCount(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    /// Marks the item at `index` as developed; the cell animates the thumbnail to full color when
    /// it observes the change.
    private func develop(_ ids: [SourceItem.ID], at index: Int) {
        guard ids.indices.contains(index) else { return }
        developedItemIDs.insert(ids[index])
    }

    /// Settles a finished run: `.idle` if it was cancelled (so the queue returns to normal),
    /// otherwise `.finished` with a success haptic when at least one item converted.
    private func settle(successCount: Int, failureCount: Int) {
        if Task.isCancelled {
            phase = .idle
            return
        }
        phase = .finished(successCount: successCount, failureCount: failureCount)
        if successCount > 0 {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// Clears a completed run's banner when the queue or options change so it can't go stale.
    private func clearFinishedState() {
        if case .finished = phase {
            phase = .idle
            developedItemIDs = []
        }
    }
}
