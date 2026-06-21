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
                Spacer()
                FilesImportButton(onPick: addFiles)
                Spacer()
                Button(role: .destructive) {
                    withAnimation(.snappy) {
                        viewModel.clearAll()
                        isGridExpanded = false
                    }
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
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

    @State private var isOptionsPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                ConvertHeader()

                if !viewModel.activeImports.isEmpty {
                    ImportingBanner()
                }

                QueueGridView(items: viewModel.items, isExpanded: $isGridExpanded) { id in
                    viewModel.remove(id)
                }

                OptionsSummaryRow(options: viewModel.options) {
                    isOptionsPresented = true
                }

                if !viewModel.skipped.isEmpty {
                    SkippedBanner(onDismiss: viewModel.clearSkipped)
                }
            }
            .padding(.horizontal, Theme.Spacing.section)
            .padding(.top, Theme.Spacing.section)
            .padding(.bottom, Theme.Spacing.majorBreak)
        }
        .sheet(isPresented: $isOptionsPresented) {
            ConversionOptionsSheet(options: $viewModel.options, entitlement: viewModel.entitlement)
        }
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
