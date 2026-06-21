//
//  ResultsSummaryTests.swift
//  HeicSwapTests
//
//  The pure logic behind the Results sheet (task 5.4): `ConversionResult` size math and the
//  `ResultsSummary` totals / savings shown atop the sheet. The sheet view, Save to Photos (add-only
//  permission), Save to Files, and Share are verified manually; these cover the numbers it can't.
//

import Foundation
import Testing
@testable import HeicSwap

struct ResultsSummaryTests {

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/results/\(name)")
    }

    // MARK: - ConversionResult

    @Suite("ConversionResult")
    struct Result {

        private func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/results/\(name)") }

        @Test("bytesSaved is the positive difference when the output shrank")
        func bytesSavedWhenSmaller() {
            let result = ConversionResult(outputURL: url("a.jpg"), originalBytes: 3_000_000, outputBytes: 1_200_000)
            #expect(result.bytesSaved == 1_800_000)
        }

        @Test("bytesSaved clamps to zero when the output grew")
        func bytesSavedClampsWhenLarger() {
            let result = ConversionResult(outputURL: url("a.png"), originalBytes: 500_000, outputBytes: 900_000)
            #expect(result.bytesSaved == 0)
        }

        @Test("isPDF reflects the output extension, case-insensitively")
        func isPDFDetection() {
            #expect(ConversionResult(outputURL: url("doc.pdf"), originalBytes: 1, outputBytes: 1).isPDF)
            #expect(ConversionResult(outputURL: url("doc.PDF"), originalBytes: 1, outputBytes: 1).isPDF)
            #expect(!ConversionResult(outputURL: url("img.jpg"), originalBytes: 1, outputBytes: 1).isPDF)
        }

        @Test("displayName is the output file name")
        func displayNameIsFileName() {
            #expect(ConversionResult(outputURL: url("IMG_0421.heic"), originalBytes: 1, outputBytes: 1).displayName == "IMG_0421.heic")
        }

        @Test("Negative inputs are clamped to zero")
        func clampsNegativeInputs() {
            let result = ConversionResult(outputURL: url("a.jpg"), originalBytes: -10, outputBytes: -5)
            #expect(result.originalBytes == 0)
            #expect(result.outputBytes == 0)
            #expect(result.bytesSaved == 0)
        }
    }

    // MARK: - Totals

    @Test("Totals sum each output's original and resulting bytes (AC1)")
    func totalsSum() {
        let results = [
            ConversionResult(outputURL: url("a.jpg"), originalBytes: 3_000_000, outputBytes: 1_000_000),
            ConversionResult(outputURL: url("b.jpg"), originalBytes: 2_000_000, outputBytes: 800_000),
        ]
        #expect(ResultsSummary.totalOriginalBytes(results) == 5_000_000)
        #expect(ResultsSummary.totalOutputBytes(results) == 1_800_000)
        #expect(ResultsSummary.totalSaved(results) == 3_200_000)
    }

    @Test("totalSaved never goes negative even when the batch grew")
    func totalSavedClamps() {
        let results = [
            ConversionResult(outputURL: url("a.png"), originalBytes: 400_000, outputBytes: 900_000),
        ]
        #expect(ResultsSummary.totalSaved(results) == 0)
        #expect(ResultsSummary.savedFraction(results) == 0)
    }

    @Test("savedFraction is the share of the original that was saved")
    func savedFractionComputed() {
        let results = [
            ConversionResult(outputURL: url("a.jpg"), originalBytes: 1_000_000, outputBytes: 250_000),
        ]
        // 750k of 1M saved → 0.75
        #expect(abs(ResultsSummary.savedFraction(results) - 0.75) < 0.0001)
    }

    @Test("savedFraction is zero with no inputs to measure")
    func savedFractionEmpty() {
        #expect(ResultsSummary.savedFraction([]) == 0)
    }

    // MARK: - Savings text

    @Test("savingsText reports the saved size and percentage when the batch shrank")
    func savingsTextWhenSaved() {
        let results = [
            ConversionResult(outputURL: url("a.jpg"), originalBytes: 1_000_000, outputBytes: 250_000),
        ]
        let text = try? #require(ResultsSummary.savingsText(for: results))
        #expect(text?.contains("75%") == true)
    }

    @Test("savingsText is nil when nothing was saved")
    func savingsTextWhenNoSavings() {
        let results = [
            ConversionResult(outputURL: url("a.png"), originalBytes: 500_000, outputBytes: 900_000),
        ]
        #expect(ResultsSummary.savingsText(for: results) == nil)
    }

    @Test("sizeText renders a non-empty file size")
    func sizeTextNonEmpty() {
        #expect(!ResultsSummary.sizeText(1_500_000).isEmpty)
        #expect(ResultsSummary.sizeText(0).isEmpty == false)
    }
}
