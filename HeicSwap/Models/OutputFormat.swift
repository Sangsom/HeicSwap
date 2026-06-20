//
//  OutputFormat.swift
//  HeicSwap
//
//  The target format a conversion produces. A format describes *what* the user wants
//  out — nothing more. Pro gating lives on batch size and advanced features (task 2.2),
//  never on the format itself, so every format is available on the free tier.
//

import Foundation
import UniformTypeIdentifiers

/// The image / document format a conversion produces.
///
/// `nonisolated` so the off-main-actor conversion engine (task 3.1) and the UI can share
/// it freely under the app's default `@MainActor` isolation. Backed by a stable raw string
/// for `Codable` persistence (the default format in Settings, task 8.1).
nonisolated enum OutputFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case jpg
    case png
    case heic
    case pdf

    var id: String { rawValue }

    /// File extension for written output (no leading dot).
    var fileExtension: String { rawValue }

    /// Uniform type identifier for `CGImageDestination`, `PhotosPicker`, and share sheets.
    var contentType: UTType {
        switch self {
        case .jpg: .jpeg
        case .png: .png
        case .heic: .heic
        case .pdf: .pdf
        }
    }

    /// Whether this is a lossy codec whose `ConversionOptions.quality` applies. PNG is
    /// lossless and PDF is a container, so neither uses quality.
    var usesQuality: Bool {
        switch self {
        case .jpg, .heic: true
        case .png, .pdf: false
        }
    }

    /// Short, user-facing label for pickers and summaries.
    var displayName: String {
        switch self {
        case .jpg: String(localized: "JPEG")
        case .png: String(localized: "PNG")
        case .heic: String(localized: "HEIC")
        case .pdf: String(localized: "PDF")
        }
    }
}
