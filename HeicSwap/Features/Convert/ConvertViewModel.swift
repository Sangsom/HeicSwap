//
//  ConvertViewModel.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 21/06/2026.
//

import PhotosUI
import SwiftUI

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
    private let analytics: any AnalyticsClient

    /// The conversion settings the Options sheet (task 5.2) edits and the Convert action (5.3)
    /// reads. Held here — not in the sheet — so choices persist as session defaults across
    /// presentations. Editing options clears a stale completion banner.
    var options = ConversionOptions() {
        didSet { clearFinishedState() }
    }

    /// The user's current entitlement, which gates the advanced options in the sheet (PRD §6) and
    /// the Convert action (task 6.3). Kept in sync with the app-wide `EntitlementStore` by the view;
    /// the model reads it as a plain value so the gate logic stays unit-testable.
    var entitlement: Entitlement

    /// The value gate that should present the paywall, or `nil` for no paywall. Drives the
    /// `.sheet(item:)` in the view (task 6.3): set directly for the Convert gate; for an
    /// options-sheet gate it's promoted from `stagedTrigger` once that sheet dismisses, so two
    /// sheets never fight to present at once.
    var paywallTrigger: ValueGate.Trigger?

    /// A gate captured while the Options sheet is still open, held until that sheet dismisses and
    /// `presentStagedPaywall()` promotes it to `paywallTrigger`.
    private var stagedTrigger: ValueGate.Trigger?

    /// The Pro action the user was attempting when the gate blocked them — replayed verbatim once
    /// they upgrade (task 6.3). `nil` when nothing is pending.
    private var pendingAction: PendingProAction?

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

    /// The options the in-flight run started with, captured so `settle` can emit
    /// `conversion_completed` even if `options` were edited afterwards (task 9.1).
    private var runOptions = ConversionOptions()

    /// When the in-flight run began, for the `duration_ms` of `conversion_completed`. A monotonic
    /// clock so it's immune to wall-clock changes mid-run.
    private var runStartedAt: ContinuousClock.Instant?

    /// The in-flight conversion, retained so a second tap can't start a parallel run, `cancel()`
    /// can stop it, and tests can await it.
    private(set) var conversionTask: Task<Void, Never>?

    init(
        importService: ImportService = ImportService(),
        engine: ConversionEngine = ConversionEngine(),
        pdfBuilder: PDFBuilder = PDFBuilder(),
        analytics: any AnalyticsClient = StubAnalyticsClient(),
        entitlement: Entitlement = .free,
        options: ConversionOptions = ConversionOptions()
    ) {
        self.importService = importService
        self.engine = engine
        self.pdfBuilder = pdfBuilder
        self.analytics = analytics
        self.entitlement = entitlement
        // Seeded from the persisted defaults in the app (task 8.1); the view keeps it in sync as the
        // defaults change. Set here so `didSet` (which clears the finished banner) doesn't run at init.
        self.options = options
    }

    /// A Pro action recorded when the value gate blocked it, so it can resume after an upgrade.
    enum PendingProAction: Equatable {
        /// The user tapped Convert on a gated run (e.g. a batch over the free limit).
        case convert
        /// The user tapped a gated control in the Options sheet; resume by applying these options.
        case applyOptions(ConversionOptions)
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

    /// True when the run targets a combined PDF — its page order can be arranged before export (5.5).
    var isPDFTarget: Bool { options.format == .pdf }

    /// Whether the PDF page order is worth arranging: a PDF target with at least two pages. A single
    /// page has no order to change, so the reorder affordance stays hidden.
    var canReorderForPDF: Bool { isPDFTarget && items.count > 1 }

    // MARK: Add

    /// Imports the picked Photos items (downloading iCloud originals on demand), appending them
    /// to the queue in selection order.
    func addFromPhotos(_ selection: [PhotosPickerItem]) async {
        clearFinishedState()
        let before = importService.items.count
        await importService.importFromPhotos(selection)
        let added = importService.items.count - before
        guard added > 0 else { return }
        // The Photos path materializes each original via `loadTransferable`, which downloads from
        // iCloud when the original is optimized-away — so every materialized photo counts as an
        // iCloud-original fetch (PRD §7 `icloud_download`). Counts only, never any content.
        analytics.log(.imagesImported(count: added, source: .photos))
        analytics.log(.icloudDownload(count: added))
    }

    /// Imports the chosen image files, appending them to the queue in order.
    func addFromFiles(_ urls: [URL]) async {
        clearFinishedState()
        let before = importService.items.count
        await importService.importFromFiles(urls)
        let added = importService.items.count - before
        guard added > 0 else { return }
        analytics.log(.imagesImported(count: added, source: .files))
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

    // MARK: Reorder (task 5.5)

    /// Reorders the queue — the PDF page order the user arranges before export. Clears a stale
    /// completion banner like the other queue mutations; `convert()` reads `items` in order, so the
    /// produced PDF matches the new arrangement.
    func moveItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        clearFinishedState()
        importService.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: Value gate → paywall (task 6.3)

    /// The gate a Convert tap would trip for the current user/queue, or `nil` when the run is free
    /// (or the user is Pro). Pro users never gate; free users gate per `ValueGate`.
    private var convertGate: ValueGate.Trigger? {
        guard !entitlement.isPro else { return nil }
        return ValueGate.proTrigger(items: items, options: options)
    }

    /// Records a gate hit (logs `pro_gate_hit`) and the action to resume after an upgrade. For the
    /// Convert gate the paywall is presented immediately; for an options-sheet gate it's staged
    /// until that sheet dismisses (`presentStagedPaywall()`), so two sheets never collide.
    private func hitGate(_ trigger: ValueGate.Trigger, resuming action: PendingProAction, staged: Bool) {
        pendingAction = action
        analytics.log(.proGateHit(gate: trigger.rawValue))
        // Hitting the free cap is a firm, slightly unyielding tap (design spec §4: `.impact(.rigid)`)
        // — felt the same whether the gate trips on Convert or on a locked option in the sheet.
        Haptics.freeCapHit()
        if staged {
            stagedTrigger = trigger
        } else {
            paywallTrigger = trigger
        }
    }

    /// Called by the Options sheet when a free user taps a Pro-gated control. Logs the gate and
    /// records the intended options so they apply after an upgrade; the paywall is presented once
    /// the Options sheet finishes dismissing.
    func requestProForOption(_ trigger: ValueGate.Trigger) {
        hitGate(trigger, resuming: .applyOptions(optionsApplying(trigger)), staged: true)
    }

    /// Promotes a staged gate to a presented paywall — call from the Options sheet's `onDismiss`.
    /// No-op when nothing was staged (the sheet was dismissed normally).
    func presentStagedPaywall() {
        guard let staged = stagedTrigger else { return }
        stagedTrigger = nil
        paywallTrigger = staged
    }

    /// Called when the paywall dismisses. If the user upgraded, the blocked action resumes (AC2);
    /// if they dismissed without buying, the pending action is dropped and they stay on the free
    /// tier (AC3). Reading `entitlement` here relies on the view having synced it from the store
    /// before the sheet's `onDismiss` fires.
    func paywallDismissed() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        guard entitlement.isPro else { return }
        switch action {
        case .convert:
            performConvert()
        case let .applyOptions(options):
            self.options = options
        }
    }

    /// The options a gated control would produce, so the action can replay after upgrade. Strip and
    /// target-size are the only options gates; the batch gate isn't an options change.
    private func optionsApplying(_ trigger: ValueGate.Trigger) -> ConversionOptions {
        var updated = options
        switch trigger {
        case .stripMetadata:
            updated.stripsMetadata = true
        case .targetSize:
            updated.resizeMode = .targetBytes(ResizeOption.defaultBytes)
        case .batchSize:
            break
        }
        return updated
    }

    // MARK: Convert (task 5.3)

    /// Runs the on-device engine over the current queue, surfacing each item's completion so its
    /// thumbnail can "develop". Image formats go through `ConversionEngine` (N→N transcode);
    /// `.pdf` goes through `PDFBuilder` (N→1 assembly). A no-op if a run is already in flight or
    /// the queue has nothing convertible.
    ///
    /// Gate first (task 6.3): a free user whose run requires Pro is sent to the paywall instead of
    /// converting, with the run recorded to resume after they upgrade (AC1/AC2).
    func convert() {
        guard !isConverting else { return }

        if let gate = convertGate {
            hitGate(gate, resuming: .convert, staged: false)
            return
        }

        performConvert()
    }

    /// Runs the conversion unconditionally — the post-gate body of `convert()`, also the resume
    /// path after a successful upgrade.
    private func performConvert() {
        // The run is actually starting — a medium impact confirms the tap (design spec §4). Fired
        // here, not at the gate check, so a gated tap feels only the rigid free-cap tap, never both.
        Haptics.convertTapped()

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
        runOptions = options
        runStartedAt = .now
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
    /// otherwise `.finished` with a success haptic when at least one item converted. A natural
    /// completion (not a cancel) emits `conversion_completed` with counts/format/duration only (AC2).
    private func settle(successCount: Int, failureCount: Int) {
        if Task.isCancelled {
            phase = .idle
            return
        }
        phase = .finished(successCount: successCount, failureCount: failureCount)
        logConversionCompleted(successCount: successCount, failureCount: failureCount)
        if successCount > 0 {
            Haptics.conversionComplete()
        }
    }

    /// Emits `conversion_completed` for a just-finished run — counts, target format, the feature
    /// flags the run used, and its wall-clock duration. No file names, no image content (AC2/AC3).
    private func logConversionCompleted(successCount: Int, failureCount: Int) {
        let durationMs = runStartedAt.map(Self.milliseconds(since:)) ?? 0
        analytics.log(.conversionCompleted(
            countSuccess: successCount,
            countFailed: failureCount,
            targetFormat: runOptions.format.rawValue,
            isBatch: conversionTotal > 1,
            usedResize: runOptions.resizeMode != .none,
            usedStrip: runOptions.stripsMetadata,
            toPDF: runOptions.format == .pdf,
            durationMs: durationMs
        ))
    }

    /// Whole milliseconds elapsed from `start` to now on the monotonic continuous clock.
    private nonisolated static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let (seconds, attoseconds) = (ContinuousClock.now - start).components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }

    /// Clears a completed run's banner when the queue or options change so it can't go stale.
    private func clearFinishedState() {
        if case .finished = phase {
            phase = .idle
            developedItemIDs = []
        }
    }
}
