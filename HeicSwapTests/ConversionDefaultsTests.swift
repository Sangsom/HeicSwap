//
//  ConversionDefaultsTests.swift
//  HeicSwapTests
//
//  The persisted conversion defaults (task 8.1): fresh installs match the `ConversionOptions()`
//  happy path, changes survive a relaunch (a new store reading the same suite), and `seedOptions`
//  projects the stored choices into the options the Convert screen starts from. The live mirroring
//  of a changed default into the Convert screen's session options is a SwiftUI `onChange` bridge,
//  verified by the manual test plan (AC1).
//

import Foundation
import Testing
@testable import HeicSwap

@MainActor
struct ConversionDefaultsTests {

    /// A fresh, isolated `UserDefaults` suite per test so persisted values never leak between cases.
    private func makeCache() -> ConversionDefaultsCache {
        ConversionDefaultsCache(defaults: UserDefaults(suiteName: "ConversionDefaultsTests-\(UUID().uuidString)")!)
    }

    @Test("A fresh install defaults to the ConversionOptions() happy path")
    func freshInstallDefaults() {
        let defaults = ConversionDefaults(cache: makeCache())

        #expect(defaults.format == .jpg)
        #expect(defaults.quality == 0.9)
        #expect(defaults.stripsMetadata == false)
        #expect(defaults.seedOptions == ConversionOptions())
    }

    @Test("Changed defaults survive a relaunch (a new store over the same suite)")
    func defaultsPersistAcrossInstances() {
        let cache = makeCache()

        let first = ConversionDefaults(cache: cache)
        first.format = .png
        first.quality = 0.6
        first.stripsMetadata = true

        // A second store over the same suite is the next launch: it reads back the saved values.
        let second = ConversionDefaults(cache: cache)
        #expect(second.format == .png)
        #expect(second.quality == 0.6)
        #expect(second.stripsMetadata == true)
    }

    @Test("seedOptions projects the stored defaults, with resize never defaulted")
    func seedOptionsReflectsDefaults() {
        let defaults = ConversionDefaults(cache: makeCache())
        defaults.format = .heic
        defaults.quality = 0.75
        defaults.stripsMetadata = true

        let seed = defaults.seedOptions
        #expect(seed.format == .heic)
        #expect(seed.quality == 0.75)
        #expect(seed.stripsMetadata == true)
        // Resize is per-batch intent, never a persisted default.
        #expect(seed.resizeMode == .none)
    }

    @Test("The cache round-trips each field independently")
    func cacheRoundTrips() {
        let cache = makeCache()

        cache.format = .pdf
        cache.quality = 0.4
        cache.stripsMetadata = true

        #expect(cache.format == .pdf)
        #expect(cache.quality == 0.4)
        #expect(cache.stripsMetadata == true)
    }

    @Test("A seeded view model starts from the provided defaults")
    func viewModelSeedsFromDefaults() {
        let defaults = ConversionDefaults(cache: makeCache())
        defaults.format = .png
        defaults.stripsMetadata = false

        let viewModel = ConvertViewModel(options: defaults.seedOptions)
        #expect(viewModel.options.format == .png)
        #expect(viewModel.options == defaults.seedOptions)
    }
}
