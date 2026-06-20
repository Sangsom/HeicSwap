//
//  CoreModelsTests.swift
//  HeicSwapTests
//
//  Construction and invariants for the core domain value types (task 2.1).
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import HeicSwap

struct CoreModelsTests {

    /// Compile-time proof that the shared value types are `Sendable` (AC1): if any type
    /// lost its conformance, these calls would fail to compile.
    private func assertSendable<T: Sendable>(_ value: T) {}

    @Test("All core value types are Sendable")
    func coreTypesAreSendable() {
        assertSendable(OutputFormat.jpg)
        assertSendable(ResizeMode.maxDimension(pixels: 2048))
        assertSendable(ConversionOptions())
        assertSendable(SourceItem.file(url: URL(filePath: "/tmp/a.heic")))
        assertSendable(ItemStatus.pending)
        assertSendable(Entitlement.pro)
    }

    @Test("No OutputFormat is inherently Pro; Pro lives on Entitlement")
    func noFormatIsInherentlyPro() {
        // Every declared format is available regardless of tier (AC2). There is no
        // per-format Pro flag — gating is batch size + advanced features (task 2.2).
        #expect(OutputFormat.allCases.count == 4)
        #expect(Entitlement.free.isPro == false)
        #expect(Entitlement.pro.isPro == true)
    }

    @Test("OutputFormat exposes a stable extension and content type")
    func outputFormatMetadata() {
        #expect(OutputFormat.jpg.fileExtension == "jpg")
        #expect(OutputFormat.jpg.contentType == .jpeg)
        #expect(OutputFormat.pdf.contentType == .pdf)
        #expect(OutputFormat.jpg.usesQuality)
        #expect(!OutputFormat.png.usesQuality)
    }

    @Test("SourceItem from a Photos asset stores the identifier and is pending")
    func sourceItemFromAsset() {
        let item = SourceItem.photoLibraryAsset(identifier: "ABC-123")
        #expect(item.source == .photoLibraryAsset(identifier: "ABC-123"))
        #expect(item.status == .pending)
    }

    @Test("SourceItem from a file stores the URL and is pending")
    func sourceItemFromFile() {
        let url = URL(filePath: "/tmp/photo.heic")
        let item = SourceItem.file(url: url)
        #expect(item.source == .file(url: url))
        #expect(item.status == .pending)
    }

    @Test("ConversionOptions defaults match the free-tier happy path")
    func conversionOptionsDefaults() {
        let options = ConversionOptions()
        #expect(options.format == .jpg)
        #expect(options.resizeMode == .none)
        #expect(options.stripsMetadata == false)
        #expect(options.quality == 0.9)
    }
}
