//
//  ResultsSheet.swift
//  HeicSwap
//
//  The Results sheet (task 5.4) — the close of the convert loop. Once a batch finishes it presents
//  every output with its resulting size and the total space saved, and offers one-tap Save to
//  Photos (add-only), Save to Files, and Share for the whole batch.
//
//  Save to Photos uses `PhotoLibrarySaver` (add-only authorization). Save to Files exports the
//  outputs through a `UIDocumentPickerViewController` so the user picks a destination. Share is a
//  native `ShareLink` over all outputs, so AirDrop / Mail / Files / third-party targets all work.
//

import SwiftUI
import UIKit

/// Presented as a large sheet when a conversion run completes, listing outputs and surfacing
/// Save / Share. Driven entirely by the `[ConversionResult]` the view model retained — it owns no
/// conversion state of its own, only the transient Save/Share UI state.
struct ResultsSheet: View {

    /// Outputs from the finished run, in order, each with its before/after size.
    let results: [ConversionResult]
    /// How many items in the run couldn't be converted (shown as a footnote).
    let failureCount: Int
    /// Clear the queue and start a fresh batch.
    let onConvertMore: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.analyticsClient) private var analytics

    @State private var photoSaveState: PhotoSaveState = .idle
    @State private var isExportingToFiles = false
    @State private var showPermissionAlert = false
    @State private var showSaveErrorAlert = false

    /// Lifecycle of the Save-to-Photos action, reflected in its button.
    private enum PhotoSaveState: Equatable { case idle, saving, saved }

    /// Every output file — what Share and Save to Files act on.
    private var allOutputs: [URL] { results.map(\.outputURL) }
    /// Image-only outputs — the photo library can't take the combined PDF.
    private var imageOutputs: [URL] { results.filter { !$0.isPDF }.map(\.outputURL) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                header
                summaryCard
                resultsList
            }
            .padding(.horizontal, Theme.Spacing.section)
            .padding(.top, Theme.Spacing.section)
            .padding(.bottom, Theme.Spacing.section)
        }
        .background(Theme.Colors.background)
        .safeAreaInset(edge: .bottom) { actionBar }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $isExportingToFiles) {
            DocumentExporter(urls: allOutputs) { didSave in
                isExportingToFiles = false
                if didSave { analytics.log(.outputSaved(destination: .files)) }
            }
            .ignoresSafeArea()
        }
        .alert(String(localized: "Allow photo access"), isPresented: $showPermissionAlert) {
            Button(String(localized: "Open Settings")) { openSettings() }
            Button(String(localized: "Not now"), role: .cancel) {}
        } message: {
            Text("To save into your photo library, allow add-only access in Settings. HeicSwap only adds photos — it never reads your library.")
        }
        .alert(String(localized: "Couldn't save to Photos"), isPresented: $showSaveErrorAlert) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text("Something went wrong saving. You can still Save to Files or Share.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                OnDeviceBadge()
                Text("Done")
                    .font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityLabel(Text(String(localized: "Close")))
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(countText)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(String(localized: "\(ResultsSummary.sizeText(ResultsSummary.totalOutputBytes(results))) total"))
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
            if let savings = ResultsSummary.savingsText(for: results) {
                Label(savings, systemImage: "arrow.down.circle.fill")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.success)
            }
            if failureCount > 0 {
                Text(failureText)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.destructive)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.item)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.input)
                .fill(Theme.Colors.surface)
        }
        .accessibilityElement(children: .combine)
    }

    private var countText: String {
        if results.count == 1 {
            return results[0].isPDF
                ? String(localized: "PDF ready")
                : String(localized: "1 file ready")
        }
        return String(localized: "\(results.count) files ready")
    }

    private var failureText: String {
        failureCount == 1
            ? String(localized: "1 item couldn't be converted")
            : String(localized: "\(failureCount) items couldn't be converted")
    }

    // MARK: List

    private var resultsList: some View {
        VStack(spacing: Theme.Spacing.small) {
            ForEach(results) { result in
                ResultRow(result: result)
            }
        }
    }

    // MARK: Actions

    private var actionBar: some View {
        VStack(spacing: Theme.Spacing.item) {
            shareButton

            HStack(spacing: Theme.Spacing.item) {
                if !imageOutputs.isEmpty {
                    SecondaryActionButton(
                        title: photoSaveState == .saved
                            ? String(localized: "Saved")
                            : String(localized: "Save to Photos"),
                        systemImage: "photo.badge.plus",
                        isBusy: photoSaveState == .saving,
                        isDone: photoSaveState == .saved
                    ) {
                        saveToPhotos()
                    }
                    .disabled(photoSaveState != .idle)
                }

                SecondaryActionButton(title: String(localized: "Save to Files"), systemImage: "folder") {
                    isExportingToFiles = true
                }
            }

            Button {
                dismiss()
                onConvertMore()
            } label: {
                Text("Convert more")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, Theme.Spacing.small)
                    .contentShape(Rectangle())
            }
            .accessibilityHint(Text(String(localized: "Clears the queue to start a new batch")))
        }
        .padding(Theme.Spacing.section)
        .background(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(height: 1)
                Theme.Colors.background
            }
            .ignoresSafeArea()
        }
    }

    private var shareButton: some View {
        ShareLink(
            items: allOutputs,
            preview: { url in SharePreview(url.lastPathComponent) },
            label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.item)
                    .background(Theme.Colors.accent, in: Capsule())
            }
        )
        // `ShareLink` exposes no completion callback, so `output_saved` is logged when share is
        // initiated (the final destination — AirDrop, Mail, … — isn't observable). A simultaneous
        // gesture records the tap without intercepting the share sheet's own presentation.
        .simultaneousGesture(TapGesture().onEnded {
            analytics.log(.outputSaved(destination: .share))
        })
        .accessibilityLabel(Text(
            allOutputs.count == 1
                ? String(localized: "Share 1 file")
                : String(localized: "Share \(allOutputs.count) files")
        ))
    }

    private func saveToPhotos() {
        guard photoSaveState == .idle else { return }
        photoSaveState = .saving
        Task {
            do {
                try await PhotoLibrarySaver.save(imageURLs: imageOutputs)
                photoSaveState = .saved
                analytics.log(.outputSaved(destination: .photos))
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch PhotoLibrarySaver.SaveError.notAuthorized {
                photoSaveState = .idle
                showPermissionAlert = true
            } catch {
                photoSaveState = .idle
                showSaveErrorAlert = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

// MARK: - Result row

/// One output: its thumbnail, name, resulting size (with the original alongside it when smaller),
/// and a saved-percentage badge.
private struct ResultRow: View {
    let result: ConversionResult

    var body: some View {
        HStack(spacing: Theme.Spacing.item) {
            ResultThumbnail(result: result)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail))

            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(result.displayName)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(sizeDetail)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer(minLength: Theme.Spacing.small)

            if savedPercent >= 1 {
                Text(verbatim: "−\(savedPercent)%")
                    .font(Theme.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.success)
            }
        }
        .padding(Theme.Spacing.item)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.input)
                .fill(Theme.Colors.surface)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    /// "2.4 MB → 1.1 MB" when the output shrank, otherwise just the output size.
    private var sizeDetail: String {
        guard result.bytesSaved > 0 else {
            return ResultsSummary.sizeText(result.outputBytes)
        }
        return "\(ResultsSummary.sizeText(result.originalBytes)) → \(ResultsSummary.sizeText(result.outputBytes))"
    }

    private var savedPercent: Int {
        guard result.originalBytes > 0, result.bytesSaved > 0 else { return 0 }
        return Int((Double(result.bytesSaved) / Double(result.originalBytes) * 100).rounded())
    }

    private var accessibilityLabel: String {
        let base = String(localized: "\(result.displayName), \(ResultsSummary.sizeText(result.outputBytes))")
        guard savedPercent >= 1 else { return base }
        return String(localized: "\(base), saved \(savedPercent) percent")
    }
}

// MARK: - Result thumbnail

/// Loads the output's thumbnail from the shared cache (off-main, with a placeholder while decoding).
/// The combined PDF has no ImageIO thumbnail, so it shows a document glyph instead.
private struct ResultThumbnail: View {
    let result: ConversionResult
    @State private var image: UIImage?

    /// ~52pt cell at 3× scale.
    private static let pixelSize = 160

    var body: some View {
        Group {
            if result.isPDF {
                placeholder(systemImage: "doc.fill")
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder(systemImage: nil)
            }
        }
        .task(id: result.outputURL) {
            guard !result.isPDF else { return }
            if let hit = ThumbnailCache.shared.cached(for: result.outputURL) {
                image = hit
            } else {
                image = await ThumbnailCache.shared.thumbnail(
                    for: result.outputURL, maxPixelSize: Self.pixelSize
                )
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func placeholder(systemImage: String?) -> some View {
        ZStack {
            Theme.Colors.surface2
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.Colors.accent)
            } else {
                ProgressView()
            }
        }
    }
}

// MARK: - Secondary action button

/// A capsule, surface-filled secondary action (Save to Photos / Save to Files) with an amber label,
/// optionally showing a spinner while busy or a checkmark once done.
private struct SecondaryActionButton: View {
    let title: String
    let systemImage: String
    var isBusy = false
    var isDone = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.small) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.Colors.accent)
                } else {
                    Image(systemName: isDone ? "checkmark" : systemImage)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(Theme.Typography.callout)
            .foregroundStyle(Theme.Colors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.item)
            .background(Theme.Colors.surface2, in: Capsule())
        }
        .accessibilityLabel(Text(title))
    }
}

// MARK: - Files export

/// Wraps `UIDocumentPickerViewController` in export mode so the user can save every output to a
/// Files destination in one pass. `asCopy: true` keeps the originals in the temp run directory
/// (Share and Save to Photos still need them). The completion closure dismisses the host sheet and
/// reports whether the user actually saved (`true`) or cancelled (`false`), so `output_saved` only
/// fires on a real save.
private struct DocumentExporter: UIViewControllerRepresentable {
    let urls: [URL]
    let onComplete: (_ didSave: Bool) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onComplete: (Bool) -> Void
        init(onComplete: @escaping (Bool) -> Void) { self.onComplete = onComplete }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onComplete(true)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete(false)
        }
    }
}

#if DEBUG
/// Writes a few solid-color JPEGs (and one fake PDF URL) so the preview exercises the real
/// thumbnail-load path and the size/savings formatting.
private func sampleResults() -> [ConversionResult] {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "results-preview", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let colors: [UIColor] = [.systemTeal, .systemIndigo, .systemPink, .systemOrange]
    let images: [ConversionResult] = (0..<4).map { index in
        let url = directory.appending(path: "IMG_204\(index).jpg")
        let data = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 180)).jpegData(withCompressionQuality: 0.9) { context in
            colors[index % colors.count].setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 180))
        }
        try? data.write(to: url)
        return ConversionResult(
            outputURL: url,
            originalBytes: 3_200_000 + index * 250_000,
            outputBytes: 1_100_000 + index * 90_000
        )
    }
    return images
}

#Preview("Results — Light") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ResultsSheet(results: sampleResults(), failureCount: 0, onConvertMore: {})
        }
        .preferredColorScheme(.light)
}

#Preview("Results — Dark") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ResultsSheet(results: sampleResults(), failureCount: 1, onConvertMore: {})
        }
        .preferredColorScheme(.dark)
}
#endif
