//
//  ValueGateTests.swift
//  HeicSwapTests
//
//  The value-gate policy (task 2.2): the free-batch boundary and each Pro trigger. Grouped into
//  nested suites so the Test navigator reads as Acceptance criteria / Boundary / Individual gates.
//

import Foundation
import Testing
@testable import HeicSwap

/// `count` distinct file-backed items, enough to drive the batch-size gate.
private func makeItems(count: Int) -> [SourceItem] {
    (0..<count).map { SourceItem.file(url: URL(filePath: "/tmp/photo-\($0).heic")) }
}

struct ValueGateTests {

    @Suite("Acceptance criteria")
    struct AcceptanceCriteria {

        @Test("AC1: a full free batch converting to JPG is free")
        func fullBatchToJPGIsFree() {
            let items = makeItems(count: ValueGate.freeBatchLimit)
            let options = ConversionOptions(format: .jpg)
            #expect(ValueGate.requiresPro(items: items, options: options) == false)
        }

        @Test("AC2: a full free batch to PDF is free (small image→PDF is not gated)")
        func fullBatchToPDFIsFree() {
            let items = makeItems(count: ValueGate.freeBatchLimit)
            let options = ConversionOptions(format: .pdf)
            #expect(ValueGate.requiresPro(items: items, options: options) == false)
        }

        @Test("AC3: batch over the limit, target-size, or strip each require Pro")
        func eachProTriggerRequiresPro() {
            let overLimit = makeItems(count: ValueGate.freeBatchLimit + 1)
            #expect(ValueGate.requiresPro(items: overLimit, options: ConversionOptions()))

            let small = makeItems(count: 1)
            #expect(ValueGate.requiresPro(
                items: small,
                options: ConversionOptions(resizeMode: .targetBytes(500_000))
            ))
            #expect(ValueGate.requiresPro(
                items: small,
                options: ConversionOptions(stripsMetadata: true)
            ))
        }
    }

    @Suite("Boundary")
    struct Boundary {

        @Test("Batch size gate trips strictly above the limit", arguments: [
            (ValueGate.freeBatchLimit - 1, false),
            (ValueGate.freeBatchLimit, false),
            (ValueGate.freeBatchLimit + 1, true),
        ])
        func batchSizeBoundary(count: Int, expected: Bool) {
            let result = ValueGate.requiresPro(items: makeItems(count: count), options: ConversionOptions())
            #expect(result == expected)
        }

        @Test("An empty batch is free")
        func emptyBatchIsFree() {
            #expect(ValueGate.requiresPro(items: [], options: ConversionOptions()) == false)
        }
    }

    @Suite("Individual gates within the free batch")
    struct IndividualGates {

        @Test("maxDimension downscale is free; only target-size gates")
        func maxDimensionIsFreeButTargetBytesGates() {
            let items = makeItems(count: 1)
            #expect(ValueGate.requiresPro(
                items: items,
                options: ConversionOptions(resizeMode: .maxDimension(pixels: 2048))
            ) == false)
            #expect(ValueGate.requiresPro(
                items: items,
                options: ConversionOptions(resizeMode: .targetBytes(1_000_000))
            ))
        }

        @Test("No output format is inherently Pro within the free batch", arguments: OutputFormat.allCases)
        func noFormatIsInherentlyPro(format: OutputFormat) {
            let items = makeItems(count: ValueGate.freeBatchLimit)
            #expect(ValueGate.requiresPro(items: items, options: ConversionOptions(format: format)) == false)
        }

        @Test("Combined triggers still require Pro")
        func combinedTriggersRequirePro() {
            let items = makeItems(count: ValueGate.freeBatchLimit + 3)
            let options = ConversionOptions(
                format: .pdf,
                resizeMode: .targetBytes(250_000),
                stripsMetadata: true
            )
            #expect(ValueGate.requiresPro(items: items, options: options))
        }
    }
}
