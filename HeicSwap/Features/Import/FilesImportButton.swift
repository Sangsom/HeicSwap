//
//  FilesImportButton.swift
//  HeicSwap
//
//  Reusable Files entry point for import (task 3.5). Presents `.fileImporter` filtered to the
//  supported image types and hands the chosen URLs back through `onPick`. The importer caps
//  selection to images for a clean UX; the import service still defensively validates each file
//  (so a renamed/corrupt file is flagged, not crashed).
//

import SwiftUI
import UniformTypeIdentifiers

struct FilesImportButton: View {
    /// Called with the chosen file URLs once the importer is dismissed.
    let onPick: ([URL]) -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Files", systemImage: "folder")
        }
        .fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: ImportService.supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result, !urls.isEmpty {
                onPick(urls)
            }
        }
    }
}
