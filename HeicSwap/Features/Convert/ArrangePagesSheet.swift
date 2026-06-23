//
//  ArrangePagesSheet.swift
//  HeicSwap
//
//  Drag-to-reorder the pages of a combined PDF before export (task 5.5). The image→PDF path is
//  HeicSwap's top acquisition surface, so once the target is PDF the user can arrange page order.
//
//  A `List` in always-on edit mode is deliberate: it gives an interactive drag handle *and* the
//  native VoiceOver reorder rotor, so the order is reachable without sight (the grid's
//  `.draggable` would not be). Reordering writes straight through to the queue via the view model,
//  and the export reads the queue in order, so the produced PDF matches what's shown here (AC2).
//

import SwiftUI
import UIKit

/// A reorderable list of the queued images as PDF pages, presented as a sheet from the Convert
/// screen when the target format is PDF. Owns no state of its own beyond presentation — the page
/// order lives on the view model's queue.
struct ArrangePagesSheet: View {
    @Bindable var viewModel: ConvertViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                        PageRow(item: item, pageNumber: index + 1, total: viewModel.items.count)
                            .listRowBackground(Theme.Colors.surface)
                    }
                    .onMove { source, destination in
                        viewModel.moveItems(fromOffsets: source, toOffset: destination)
                    }
                } footer: {
                    Text("Pages export top to bottom. Drag the handle to reorder.")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            // Always editable — the drag handles (and VoiceOver's reorder control) are available
            // without an Edit button, so reordering is one gesture / one rotor action.
            .environment(\.editMode, .constant(.active))
            .navigationTitle(Text("Arrange pages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done")) { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Page row

/// One PDF page: its 1-based page number, a thumbnail, and the source's file name. The whole row is
/// a single VoiceOver element; the List's edit mode supplies the reorder control alongside it.
private struct PageRow: View {
    let item: SourceItem
    let pageNumber: Int
    let total: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.item) {
            Text(verbatim: "\(pageNumber)")
                .font(Theme.Typography.headline)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.accent)
                .frame(minWidth: 24, alignment: .center)

            PageThumbnail(source: item.source)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail))

            Text(name)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: Theme.Spacing.small)
        }
        .padding(.vertical, Theme.Spacing.tight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Page \(pageNumber) of \(total), \(name)")))
    }

    /// The source file's name, or a stable fallback for the (placeholder) asset case.
    private var name: String {
        switch item.source {
        case let .file(url): url.lastPathComponent
        case .photoLibraryAsset: String(localized: "Photo")
        }
    }
}

// MARK: - Thumbnail

/// Loads a page's thumbnail from the shared cache (synchronously on a hit, otherwise off-main),
/// showing a surface placeholder while decoding. Mirrors the queue / results thumbnail pattern.
private struct PageThumbnail: View {
    let source: SourceItem.Source
    @State private var image: UIImage?

    /// ~48pt cell at 3× scale.
    private static let pixelSize = 160

    var body: some View {
        Group {
            switch source {
            case .file:
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder(systemImage: nil)
                }
            case .photoLibraryAsset:
                placeholder(systemImage: "photo")
            }
        }
        .task(id: fileURL) {
            guard let url = fileURL else { return }
            if let hit = ThumbnailCache.shared.cached(for: url) {
                image = hit
            } else {
                image = await ThumbnailCache.shared.thumbnail(for: url, maxPixelSize: Self.pixelSize)
            }
        }
        .accessibilityHidden(true)
    }

    private var fileURL: URL? {
        if case let .file(url) = source { return url }
        return nil
    }

    @ViewBuilder private func placeholder(systemImage: String?) -> some View {
        ZStack {
            Theme.Colors.surface2
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ProgressView()
            }
        }
    }
}

#if DEBUG
/// Seeds a view model with a few real sample images (varied aspect ratios) and presents the sheet,
/// so the canvas exercises the populated reorder list and the real thumbnail-load path.
private struct ArrangePagesPreviewHost: View {
    @State private var viewModel = ConvertViewModel()

    var body: some View {
        Color.clear
            .task {
                guard viewModel.items.isEmpty else { return }
                await viewModel.addFromFiles(Self.sampleImageURLs(4))
                viewModel.options.format = .pdf
            }
            .sheet(isPresented: .constant(true)) {
                ArrangePagesSheet(viewModel: viewModel)
            }
    }

    private static func sampleImageURLs(_ count: Int) -> [URL] {
        let sizes: [CGSize] = [
            CGSize(width: 400, height: 300), CGSize(width: 300, height: 400),
            CGSize(width: 600, height: 200), CGSize(width: 350, height: 350),
        ]
        let colors: [UIColor] = [.systemTeal, .systemIndigo, .systemPink, .systemBrown]
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "arrange-preview", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (0..<count).map { index in
            let size = sizes[index % sizes.count]
            let url = directory.appending(path: "page-\(index).png")
            let data = UIGraphicsImageRenderer(size: size).pngData { context in
                colors[index % colors.count].setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            try? data.write(to: url)
            return url
        }
    }
}

#Preview("Arrange pages — Light") {
    ArrangePagesPreviewHost()
        .preferredColorScheme(.light)
}

#Preview("Arrange pages — Dark") {
    ArrangePagesPreviewHost()
        .preferredColorScheme(.dark)
}
#endif
