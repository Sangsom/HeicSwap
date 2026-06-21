//
//  QueueGridView.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 21/06/2026.
//

import SwiftUI
import UIKit

/// The Convert queue as a 4-column thumbnail grid with a soft safelight glow (task 5.1).
///
/// Collapsed, it shows a capped preview (`previewCap` cells) with a tappable "+N" tile standing in
/// for the rest, keeping the whole flow on one screen (design spec §3). Tapping "+N" expands to the
/// full queue so every item stays reachable and removable. Each thumbnail removes via its ✕ or a
/// long-press menu.
struct QueueGridView: View {

    let items: [SourceItem]
    @Binding var isExpanded: Bool
    /// True while a batch conversion is running — dims every not-yet-finished thumbnail and hides
    /// the remove controls (you can't edit the queue mid-convert).
    var isConverting: Bool = false
    /// Ids of items that have finished this run; their thumbnails render fully "developed".
    var developedItemIDs: Set<SourceItem.ID> = []
    let onRemove: (SourceItem.ID) -> Void

    /// Longest-edge pixel size requested from `ThumbnailCache` — ~100pt cells at 3× scale.
    static let thumbnailPixelSize = 300
    /// Grid cells the collapsed preview may use before folding the rest into "+N" (2 rows of 4).
    private static let previewCap = 8

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.small),
        count: 4
    )

    var body: some View {
        let split = QueueLayout.split(total: items.count, cap: Self.previewCap, isExpanded: isExpanded)
        let visibleItems = items.prefix(split.visible)

        LazyVGrid(columns: columns, spacing: Theme.Spacing.small) {
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                QueueCell(
                    item: item,
                    position: index + 1,
                    total: items.count,
                    // Developed when nothing is converting, or once this item has finished.
                    isDeveloped: !isConverting || developedItemIDs.contains(item.id),
                    isConverting: isConverting
                ) {
                    onRemove(item.id)
                }
            }

            if split.overflow > 0 {
                OverflowTile(count: split.overflow) {
                    withAnimation(.snappy) { isExpanded = true }
                }
            }
        }
        .padding(Theme.Spacing.section)
        .background {
            // Safelight glow — applied sparingly: a low-opacity, heavily blurred wash behind the grid.
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(Theme.Gradients.safelight)
                .opacity(0.14)
                .blur(radius: 24)
        }
        .animation(.snappy, value: items)
    }
}

// MARK: - Cell

/// One queued image: a square, rounded thumbnail with a ✕ remove control and a long-press menu.
private struct QueueCell: View {
    let item: SourceItem
    /// 1-based position, for the VoiceOver label.
    let position: Int
    let total: Int
    /// Whether this item's thumbnail shows in full color (`true`) or in the dimmed "undeveloped"
    /// state it animates out of as it finishes converting (task 5.3).
    var isDeveloped: Bool = true
    /// True while a batch conversion is running — hides the remove affordances.
    var isConverting: Bool = false
    let onRemove: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let reveal = DevelopReveal.style(isDeveloped: isDeveloped, reduceMotion: reduceMotion)

        // A flexible square sized to the grid column; the image fills it as a clipped overlay so
        // every cell is a uniform rounded square regardless of the source's aspect ratio.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                thumbnail
                    .saturation(reveal.saturation)
                    .brightness(reveal.brightness)
                    .opacity(reveal.opacity)
                    .animation(.easeIn(duration: DevelopReveal.duration), value: isDeveloped)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail))
            .overlay(alignment: .topTrailing) {
                if !isConverting { removeButton }
            }
            .contextMenu {
                if !isConverting {
                    Button(role: .destructive, action: onRemove) {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
            // One VoiceOver element per cell with a Remove action; the small ✕ is a touch affordance.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(String(localized: "Photo \(position) of \(total)")))
            .accessibilityAction(named: Text(String(localized: "Remove"))) {
                if !isConverting { onRemove() }
            }
    }

    @ViewBuilder private var thumbnail: some View {
        switch item.source {
        case let .file(url):
            QueueThumbnail(url: url)
        case .photoLibraryAsset:
            // Current import always materializes to a file; placeholder for completeness.
            ZStack {
                Theme.Colors.surface2
                Image(systemName: "photo")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Theme.Colors.onAccent, Theme.Colors.accent)
                .shadow(radius: 2)
                .padding(Theme.Spacing.tight)
        }
        // ≥44pt tap target even though the glyph is small.
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
}

// MARK: - Thumbnail

/// Loads its image from `ThumbnailCache` (synchronously on a cache hit, otherwise off-main),
/// showing a surface placeholder while decoding.
private struct QueueThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Theme.Colors.surface2
                    ProgressView()
                }
            }
        }
        .task(id: url) {
            if let hit = ThumbnailCache.shared.cached(for: url) {
                image = hit
            } else {
                image = await ThumbnailCache.shared.thumbnail(
                    for: url, maxPixelSize: QueueGridView.thumbnailPixelSize
                )
            }
        }
    }
}

// MARK: - Overflow tile

/// The "+N" tile that stands in for items beyond the collapsed preview; tap to expand.
private struct OverflowTile: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.thumbnail)
                    .fill(Theme.Colors.surface2)
                Text(verbatim: "+\(count)")
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "Show \(count) more")))
    }
}

#if DEBUG
// Writes real sample images of varied aspect ratios (with a circle, to expose any distortion) so
// the preview exercises the actual decode + crop-to-square path — confirming non-square sources
// fill uniform cells rather than overflowing the grid.
private func sampleItems(_ count: Int) -> [SourceItem] {
    let sizes: [CGSize] = [
        CGSize(width: 400, height: 300), CGSize(width: 300, height: 400),
        CGSize(width: 600, height: 200), CGSize(width: 350, height: 350),
    ]
    let colors: [UIColor] = [.systemTeal, .systemIndigo, .systemPink, .systemBrown]
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "queue-preview", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    return (0..<count).map { index in
        let size = sizes[index % sizes.count]
        let url = directory.appending(path: "sample-\(index).png")
        let data = UIGraphicsImageRenderer(size: size).pngData { context in
            colors[index % colors.count].setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.withAlphaComponent(0.85).setStroke()
            let diameter = min(size.width, size.height) * 0.8
            let circle = CGRect(
                x: (size.width - diameter) / 2, y: (size.height - diameter) / 2,
                width: diameter, height: diameter
            )
            let path = UIBezierPath(ovalIn: circle)
            path.lineWidth = 8
            path.stroke()
        }
        try? data.write(to: url)
        return SourceItem.file(url: url)
    }
}

#Preview("Collapsed +N — Light") {
    QueueGridView(items: sampleItems(12), isExpanded: .constant(false), onRemove: { _ in })
        .padding()
        .background(Theme.Colors.background)
        .preferredColorScheme(.light)
}

#Preview("Collapsed +N — Dark") {
    QueueGridView(items: sampleItems(12), isExpanded: .constant(false), onRemove: { _ in })
        .padding()
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
}

#Preview("Expanded") {
    QueueGridView(items: sampleItems(12), isExpanded: .constant(true), onRemove: { _ in })
        .padding()
        .background(Theme.Colors.background)
}
#endif
