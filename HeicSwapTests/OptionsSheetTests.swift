//
//  OptionsSheetTests.swift
//  HeicSwapTests
//
//  The pure presentation logic behind the Options sheet (task 5.2): the one-line options summary
//  shown on the Convert screen, and the `ResizeMode` ↔ `ResizeOption` projection that drives the
//  resize picker and its Pro gate. The sheet view itself is verified manually (Dark Mode /
//  VoiceOver / Dynamic Type); these cover the logic it can't.
//

import Foundation
import Testing
@testable import HeicSwap

struct OptionsSheetTests {

    // MARK: - Options summary

    @Suite("Options summary")
    struct Summary {

        @Test("Lossy format shows format and quality")
        func lossyFormatWithQuality() {
            let options = ConversionOptions(format: .jpg, quality: 0.9)
            #expect(OptionsSummary.text(for: options) == "JPEG · 90%")
        }

        @Test("Lossless format omits quality", arguments: [OutputFormat.png, .pdf])
        func losslessFormatOmitsQuality(_ format: OutputFormat) {
            let options = ConversionOptions(format: format)
            #expect(OptionsSummary.text(for: options) == format.displayName)
        }

        @Test("Max-dimension resize appears in the summary")
        func maxDimensionInSummary() {
            let options = ConversionOptions(format: .heic, quality: 0.9, resizeMode: .maxDimension(pixels: 2048))
            #expect(OptionsSummary.text(for: options) == "HEIC · 90% · Max 2048 px")
        }

        @Test("Stripping metadata appears in the summary")
        func stripInSummary() {
            let options = ConversionOptions(format: .jpg, quality: 0.9, stripsMetadata: true)
            #expect(OptionsSummary.text(for: options) == "JPEG · 90% · No metadata")
        }

        @Test("Every applicable fragment is joined in order")
        func combinedSummary() {
            let options = ConversionOptions(
                format: .jpg, quality: 0.5, resizeMode: .maxDimension(pixels: 1024), stripsMetadata: true
            )
            #expect(OptionsSummary.text(for: options) == "JPEG · 50% · Max 1024 px · No metadata")
        }

        @Test("Target-size resize labels its byte target", arguments: [
            (1_000_000, "MB"), (500_000, "KB"),
        ])
        func targetSizeInSummary(bytes: Int, unit: String) {
            // The byte label is locale-formatted via ByteCountFormatter, so assert the stable parts.
            let options = ConversionOptions(format: .jpg, quality: 0.9, resizeMode: .targetBytes(bytes))
            let text = OptionsSummary.text(for: options)
            #expect(text.hasPrefix("JPEG · 90% · ≤ "))
            #expect(text.contains(unit))
        }

        @Test("Quality rounds to a whole percent", arguments: [
            (0.9, "90%"), (0.85, "85%"), (1.0, "100%"), (0.333, "33%"),
        ])
        func qualityRounding(quality: Double, expected: String) {
            #expect(OptionsSummary.qualityText(quality) == expected)
        }
    }

    // MARK: - Resize option projection

    @Suite("Resize option")
    struct Resize {

        @Test("Each mode projects to its choice")
        func modeProjectsToChoice() {
            #expect(ResizeOption(.none) == .original)
            #expect(ResizeOption(.maxDimension(pixels: 2048)) == .maxDimension)
            #expect(ResizeOption(.targetBytes(1_000_000)) == .targetSize)
        }

        @Test("Only target file size requires Pro")
        func onlyTargetSizeRequiresPro() {
            #expect(ResizeOption.original.requiresPro == false)
            #expect(ResizeOption.maxDimension.requiresPro == false)
            #expect(ResizeOption.targetSize.requiresPro == true)
        }

        @Test("Building a mode uses the right value per choice")
        func modeBuilder() {
            #expect(ResizeOption.original.mode(pixels: 2048, bytes: 1_000_000) == .none)
            #expect(ResizeOption.maxDimension.mode(pixels: 2048, bytes: 1_000_000) == .maxDimension(pixels: 2048))
            #expect(ResizeOption.targetSize.mode(pixels: 2048, bytes: 1_000_000) == .targetBytes(1_000_000))
        }

        @Test("Choice survives a round trip through a built mode", arguments: ResizeOption.allCases)
        func roundTrip(option: ResizeOption) {
            let mode = option.mode(pixels: ResizeOption.defaultPixels, bytes: ResizeOption.defaultBytes)
            #expect(ResizeOption(mode) == option)
        }
    }
}
