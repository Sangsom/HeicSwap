//
//  ConvertView.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 21/06/2026.
//

import PhotosUI
import SwiftUI

/// The root of the app — a `NavigationStack` hosting the Convert screen.
///
/// The heart of the app on one screen (task 5.1): the serif title, the persistent on-device trust
/// badge, and the queue of images to convert — a thumbnail grid fed by the import service, or an
/// inviting empty state when nothing's queued. Settings is reachable from the nav bar. The format
/// row (5.2) and the Convert action (5.3) slot in below the grid next.
struct ConvertView: View {
    @State private var viewModel: ConvertViewModel
    @State private var path: [ConvertRoute] = []
    @State private var isGridExpanded = false

    /// The persisted conversion defaults (task 8.1). The view model is seeded from these at launch;
    /// here we mirror later changes — made in Settings — into the live session options so a changed
    /// default is reflected the next time the Options sheet opens (AC1).
    @Environment(\.conversionDefaults) private var conversionDefaults

    /// View model injected via the initializer (default-constructed for the app and previews).
    init(viewModel: ConvertViewModel = ConvertViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Colors.background
                    .ignoresSafeArea()

                if viewModel.isEmpty {
                    ConvertEmptyState(onAddPhotos: addPhotos, onAddFiles: addFiles)
                } else {
                    ConvertQueueContent(viewModel: viewModel, isGridExpanded: $isGridExpanded)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .navigationDestination(for: ConvertRoute.self) { route in
                switch route {
                case .settings:
                    SettingsScreen()
                }
            }
        }
        // Mirror each persisted default into the live session options as it changes in Settings —
        // per field, so a default change never clobbers an unrelated in-session choice (AC1).
        .onChange(of: conversionDefaults.format) { _, format in
            viewModel.options.format = format
        }
        .onChange(of: conversionDefaults.quality) { _, quality in
            viewModel.options.quality = quality
        }
        .onChange(of: conversionDefaults.stripsMetadata) { _, stripsMetadata in
            viewModel.options.stripsMetadata = stripsMetadata
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                path.append(.settings)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }

        if !viewModel.isEmpty {
            ToolbarItemGroup(placement: .bottomBar) {
                PhotosImportButton(onPick: addPhotos)
                    .disabled(viewModel.isConverting)
                Spacer()
                FilesImportButton(onPick: addFiles)
                    .disabled(viewModel.isConverting)
                Spacer()
                Button(role: .destructive) {
                    withAnimation(.snappy) {
                        viewModel.clearAll()
                        isGridExpanded = false
                    }
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .disabled(viewModel.isConverting)
            }
        }
    }

    // MARK: Actions

    private func addPhotos(_ selection: [PhotosPickerItem]) {
        Task { await viewModel.addFromPhotos(selection) }
    }

    private func addFiles(_ urls: [URL]) {
        Task { await viewModel.addFromFiles(urls) }
    }
}

/// Type-safe push destinations for the Convert stack. Phase 5 extends this.
enum ConvertRoute: Hashable {
    case settings
}

// MARK: - Header

/// Serif "Convert" title with the persistent on-device trust badge — shared by both states.
private struct ConvertHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            OnDeviceBadge()

            Text("Convert")
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }
}

// MARK: - Loaded queue

/// The populated state: the thumbnail grid, the output-options row that presents the sheet, plus
/// any in-flight / skipped import status.
private struct ConvertQueueContent: View {
    @Bindable var viewModel: ConvertViewModel
    @Binding var isGridExpanded: Bool

    @Environment(\.entitlementStore) private var entitlementStore

    @State private var isOptionsPresented = false
    @State private var isResultsPresented = false
    @State private var isArrangePresented = false

    /// Items the just-finished run couldn't convert — surfaced in the Results sheet footnote.
    private var failureCount: Int {
        if case let .finished(_, failures) = viewModel.phase { failures } else { 0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                ConvertHeader()

                if !viewModel.activeImports.isEmpty {
                    ImportingBanner()
                }

                QueueGridView(
                    items: viewModel.items,
                    isExpanded: $isGridExpanded,
                    isConverting: viewModel.isConverting,
                    developedItemIDs: viewModel.developedItemIDs
                ) { id in
                    viewModel.remove(id)
                }

                OptionsSummaryRow(options: viewModel.options) {
                    isOptionsPresented = true
                }
                .disabled(viewModel.isConverting)

                if viewModel.canReorderForPDF {
                    ArrangePagesRow(pageCount: viewModel.items.count) {
                        isArrangePresented = true
                    }
                    .disabled(viewModel.isConverting)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                ConvertActionSection(
                    viewModel: viewModel,
                    onConvert: startConvert,
                    onShowResults: { isResultsPresented = true }
                )

                if !viewModel.skipped.isEmpty {
                    SkippedBanner(onDismiss: viewModel.clearSkipped)
                }
            }
            .padding(.horizontal, Theme.Spacing.section)
            .padding(.top, Theme.Spacing.section)
            .padding(.bottom, Theme.Spacing.majorBreak)
            .animation(.snappy, value: viewModel.canReorderForPDF)
        }
        // Keep the model's entitlement in lockstep with the app-wide store, so the gate (task 6.3)
        // and the options-sheet locks read the live Pro state — including a Pro user at launch.
        .onChange(of: entitlementStore.entitlement, initial: true) { _, entitlement in
            viewModel.entitlement = entitlement
        }
        .sheet(isPresented: $isOptionsPresented, onDismiss: viewModel.presentStagedPaywall) {
            ConversionOptionsSheet(
                options: $viewModel.options,
                entitlement: viewModel.entitlement,
                onProLockTapped: { trigger in
                    viewModel.requestProForOption(trigger)
                    isOptionsPresented = false
                }
            )
        }
        .sheet(item: $viewModel.paywallTrigger, onDismiss: paywallDismissed) { trigger in
            PaywallSheet(trigger: trigger.rawValue)
        }
        .sheet(isPresented: $isArrangePresented) {
            ArrangePagesSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isResultsPresented) {
            ResultsSheet(
                results: viewModel.lastResults,
                failureCount: failureCount,
                onConvertMore: convertMore
            )
        }
        // Surface the Results sheet automatically the moment a run finishes with at least one
        // converted output — "one tap from done" (the tap was Convert).
        .onChange(of: viewModel.phase) { _, newPhase in
            if case let .finished(successCount, _) = newPhase,
               successCount > 0, !viewModel.lastResults.isEmpty {
                isResultsPresented = true
            }
        }
    }

    /// On paywall dismissal, sync the freshest entitlement from the store (a purchase mutates it),
    /// then let the model resume the blocked action if the user upgraded (AC2), or stay free (AC3).
    private func paywallDismissed() {
        viewModel.entitlement = entitlementStore.entitlement
        viewModel.paywallDismissed()
    }

    /// Expands the grid so every thumbnail is on screen to "develop", then starts the run.
    private func startConvert() {
        withAnimation(.snappy) { isGridExpanded = true }
        viewModel.convert()
    }

    /// Clears the finished batch so the screen returns to a fresh, empty queue for the next run.
    private func convertMore() {
        withAnimation(.snappy) {
            viewModel.clearAll()
            isGridExpanded = false
        }
    }
}

// MARK: - Convert action

/// The primary Convert action below the options row: the CTA when idle, a live progress bar with
/// Cancel while converting, and a completion banner (plus a re-convert CTA) when finished (task 5.3).
private struct ConvertActionSection: View {
    @Bindable var viewModel: ConvertViewModel
    let onConvert: () -> Void
    /// Re-opens the Results sheet (it auto-presents on completion; this is for after a dismiss).
    let onShowResults: () -> Void

    var body: some View {
        switch viewModel.phase {
        case .idle:
            convertButton
        case .converting:
            ConvertingProgress(
                converted: viewModel.convertedCount,
                total: viewModel.conversionTotal,
                onCancel: viewModel.cancelConversion
            )
        case let .finished(successCount, failureCount):
            VStack(spacing: Theme.Spacing.item) {
                ConvertedBanner(
                    successCount: successCount,
                    failureCount: failureCount,
                    onTap: successCount > 0 ? onShowResults : nil
                )
                convertButton
            }
        }
    }

    @ViewBuilder private var convertButton: some View {
        if !viewModel.items.isEmpty {
            ConvertButton(
                count: viewModel.items.count,
                format: viewModel.options.format,
                action: onConvert
            )
        }
    }
}

/// The amber "Convert" CTA — dark ink on safelight amber, full-width capsule.
private struct ConvertButton: View {
    let count: Int
    let format: OutputFormat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.item)
                .background(Theme.Colors.accent, in: Capsule())
        }
        .accessibilityLabel(Text(title))
    }

    private var title: String {
        if format == .pdf {
            return count == 1
                ? String(localized: "Make a PDF")
                : String(localized: "Combine \(count) into a PDF")
        }
        return count == 1
            ? String(localized: "Convert 1 photo")
            : String(localized: "Convert \(count) photos")
    }
}

/// The live "developing" state: how many of how many have finished, a determinate bar, and Cancel.
private struct ConvertingProgress: View {
    let converted: Int
    let total: Int
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                Text("Developing… \(converted) of \(total)")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Button(role: .cancel, action: onCancel) {
                    Text("Cancel")
                }
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.accent)
            }
            ProgressView(value: Double(converted), total: Double(max(total, 1)))
                .tint(Theme.Colors.accent)
        }
        .padding(Theme.Spacing.item)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.input)
                .fill(Theme.Colors.surface)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(localized: "Converting")))
        .accessibilityValue(Text(String(localized: "\(converted) of \(total) done")))
    }
}

/// Completion confirmation after a run finishes. When `onTap` is set, the whole banner re-opens the
/// Results sheet (task 5.4) to Save or Share — the sheet also auto-presents the moment a run ends.
private struct ConvertedBanner: View {
    let successCount: Int
    let failureCount: Int
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let onTap {
            Button(action: onTap) { banner }
                .buttonStyle(.plain)
                .accessibilityHint(Text(String(localized: "Opens results to save or share")))
        } else {
            banner
        }
    }

    private var banner: some View {
        HStack(spacing: Theme.Spacing.item) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Theme.Colors.success)
            Text(message)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            if onTap != nil {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .padding(Theme.Spacing.item)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.input)
                .fill(Theme.Colors.surface)
        }
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        if failureCount > 0 {
            return String(localized: "Converted \(successCount), \(failureCount) couldn't be converted")
        }
        return successCount == 1
            ? String(localized: "Converted 1 photo")
            : String(localized: "Converted \(successCount) photos")
    }
}

// MARK: - Options summary row

/// The tappable "Output" row beneath the grid: a glance at the current conversion settings and the
/// entry point to the Options sheet (task 5.2).
private struct OptionsSummaryRow: View {
    let options: ConversionOptions
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.item) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text("Output")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(OptionsSummary.text(for: options))
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.item)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.input)
                    .fill(Theme.Colors.surface)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Output options")))
        .accessibilityValue(Text(OptionsSummary.text(for: options)))
        .accessibilityHint(Text(String(localized: "Choose format, quality, resize, and metadata")))
    }
}

// MARK: - Arrange pages row

/// The entry point to drag-to-reorder PDF pages (task 5.5), shown beneath the options row only when
/// the target is a multi-page PDF. Surfaces the PDF path prominently — when you're combining photos
/// into a PDF, arranging their order is one tap away.
private struct ArrangePagesRow: View {
    let pageCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.item) {
                Image(systemName: "list.number")
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text("PDF pages")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text("Arrange \(pageCount) pages")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.item)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.input)
                    .fill(Theme.Colors.surface)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Arrange PDF pages")))
        .accessibilityValue(Text(String(localized: "\(pageCount) pages")))
        .accessibilityHint(Text(String(localized: "Drag to reorder pages before export")))
    }
}

// MARK: - Empty state

/// First-run / empty queue: a warm invitation with a prominent Add Photos action and a Files
/// secondary. Both add affordances live here, so the bottom toolbar only appears once there's a
/// queue to manage.
private struct ConvertEmptyState: View {
    let onAddPhotos: ([PhotosPickerItem]) -> Void
    let onAddFiles: ([URL]) -> Void

    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isPhotosPickerPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            ConvertHeader()
            invitation
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, Theme.Spacing.section)
        .padding(.top, Theme.Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var invitation: some View {
        VStack(spacing: Theme.Spacing.sectionGap) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56))
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityHidden(true)

            VStack(spacing: Theme.Spacing.small) {
                Text("Drop in a photo to begin")
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Convert, resize, or turn photos into a PDF — all on your iPhone, never uploaded.")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            addButtons
                .padding(.top, Theme.Spacing.small)
        }
    }

    private var addButtons: some View {
        VStack(spacing: Theme.Spacing.item) {
            // Presented via `.photosPicker` so the trust-styled label (dark ink on amber) is ours —
            // `PhotosImportButton`'s `@Sendable` label can't carry custom styling.
            Button {
                isPhotosPickerPresented = true
            } label: {
                Label("Add Photos", systemImage: "photo.badge.plus")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.onAccent)
                    .padding(.horizontal, Theme.Spacing.majorBreak)
                    .padding(.vertical, Theme.Spacing.item)
                    .background(Theme.Colors.accent, in: Capsule())
            }
            .photosPicker(
                isPresented: $isPhotosPickerPresented,
                selection: $photoSelection,
                maxSelectionCount: nil,
                selectionBehavior: .ordered,
                matching: .images
            )
            .onChange(of: photoSelection) { _, newSelection in
                guard !newSelection.isEmpty else { return }
                onAddPhotos(newSelection)
                photoSelection = []
            }

            FilesImportButton(onPick: onAddFiles)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.accent)
        }
    }
}

// MARK: - Import status banners

/// Shown while Photos originals download (the iCloud-optimized case), reinforcing the promise.
private struct ImportingBanner: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.item) {
            ProgressView()
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text("Downloading from iCloud…")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Nothing leaves your iPhone.")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(Theme.Spacing.item)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.input)
                .fill(Theme.Colors.surface)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Inline note when some inputs were skipped because they aren't usable images.
private struct SkippedBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.item) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Colors.destructive)
            Text("Some items couldn't be added — they aren't supported images.")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Button("Dismiss", action: onDismiss)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.accent)
        }
        .padding(Theme.Spacing.item)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.input)
                .fill(Theme.Colors.surface)
        }
    }
}

#Preview("Empty — Light") {
    ConvertView()
        .preferredColorScheme(.light)
}

#Preview("Empty — Dark") {
    ConvertView()
        .preferredColorScheme(.dark)
}

// Bare empty state (no NavigationStack/toolbar) — also a canvas-friendly preview of just the
// invitation, since the full-screen preview can hit Xcode's preview-instrumentation limits.
#Preview("Empty state — Light") {
    ConvertEmptyState(onAddPhotos: { _ in }, onAddFiles: { _ in })
        .background(Theme.Colors.background)
        .preferredColorScheme(.light)
}

#Preview("Empty state — Dark") {
    ConvertEmptyState(onAddPhotos: { _ in }, onAddFiles: { _ in })
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
}

// The three Convert action states (task 5.3), stacked for a quick Light/Dark + Dynamic Type check.
#Preview("Convert action states") {
    VStack(spacing: Theme.Spacing.sectionGap) {
        ConvertButton(count: 12, format: .jpg, action: {})
        ConvertButton(count: 8, format: .pdf, action: {})
        ConvertingProgress(converted: 7, total: 12, onCancel: {})
        ConvertedBanner(successCount: 12, failureCount: 0)
        ConvertedBanner(successCount: 10, failureCount: 2)
    }
    .padding(Theme.Spacing.section)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.Colors.background)
}
