//
//  ImportView.swift
//  HeicSwap
//
//  Manual-verification harness for the import service (task 3.5). Composes the reusable
//  `PhotosImportButton` / `FilesImportButton` and shows live import state: in-flight downloads
//  with a "Downloading from iCloud…" indicator + progress, the ready queue, and any flagged
//  skips. The real Convert shell (task 4.1) and queue UI (task 5.1) replace this surface; it
//  exists so the import service can be exercised end-to-end on device today.
//

import PhotosUI
import SwiftUI

struct ImportView: View {
    @State private var importService = ImportService()

    var body: some View {
        NavigationStack {
            List {
                if !importService.active.isEmpty {
                    Section(String(localized: "Importing")) {
                        ForEach(importService.active) { item in
                            ActiveImportRow(item: item)
                        }
                    }
                }

                Section(String(localized: "In queue (\(importService.items.count))")) {
                    if importService.items.isEmpty {
                        Text("Pick photos or files to get started.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(importService.items) { item in
                            Label(item.displayName, systemImage: "photo")
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                importService.remove(importService.items[index].id)
                            }
                        }
                    }
                }

                if !importService.skipped.isEmpty {
                    Section {
                        ForEach(importService.skipped) { skip in
                            SkippedImportRow(skip: skip)
                        }
                    } header: {
                        Text("Skipped")
                    } footer: {
                        Button(String(localized: "Clear skipped")) {
                            importService.clearSkipped()
                        }
                    }
                }
            }
            .navigationTitle("Import")
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    PhotosImportButton { items in
                        Task { await importService.importFromPhotos(items) }
                    }
                    Spacer()
                    FilesImportButton { urls in
                        Task { await importService.importFromFiles(urls) }
                    }
                }
            }
        }
    }
}

// MARK: - Rows

private struct ActiveImportRow: View {
    let item: ActiveImport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.label)
            switch item.status {
            case .failed:
                Label(item.message ?? String(localized: "Import failed"), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            default:
                if let fraction = item.fractionCompleted {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
                Text("Downloading from iCloud…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SkippedImportRow: View {
    let skip: ImportSkip

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(skip.label)
            Text(skip.reason.errorDescription ?? String(localized: "Skipped"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Display helpers

private extension SourceItem {
    /// A short, user-facing name for a queued item.
    var displayName: String {
        switch source {
        case let .file(url):
            url.lastPathComponent
        case let .photoLibraryAsset(identifier):
            identifier
        }
    }
}

#Preview {
    ImportView()
}
