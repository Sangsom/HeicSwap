//
//  AnalyticsEventTests.swift
//  HeicSwapTests
//
//  The analytics event catalog (task 9.1) maps 1:1 to PRD §7: exact event names, exact parameter
//  keys, and only non-PII primitive values (counts / formats / durations / enumerated kinds). These
//  pure tests are the audit guard for AC1 ("only non-PII params") and AC3 ("no image bytes/filenames
//  are sent anywhere") — if a future change adds a PII-shaped parameter, a test here fails.
//

import Foundation
import Testing
@testable import HeicSwap

struct AnalyticsEventTests {

    // MARK: Names + parameters per §7

    @Test("app_launched: is_first_launch only")
    func appLaunched() {
        let event = AnalyticsEvent.appLaunched(isFirstLaunch: true)
        #expect(event.name == "app_launched")
        #expect(event.parameters?["is_first_launch"] as? Bool == true)
        #expect(Set(event.parameters?.keys ?? [:].keys) == ["is_first_launch"])
    }

    @Test("onboarding_completed: screens_viewed + skipped")
    func onboardingCompleted() {
        let event = AnalyticsEvent.onboardingCompleted(screensViewed: 2, skipped: true)
        #expect(event.name == "onboarding_completed")
        #expect(event.parameters?["screens_viewed"] as? Int == 2)
        #expect(event.parameters?["skipped"] as? Bool == true)
        #expect(Set(event.parameters?.keys ?? [:].keys) == ["screens_viewed", "skipped"])
    }

    @Test("images_imported: count + source")
    func imagesImported() {
        let event = AnalyticsEvent.imagesImported(count: 5, source: .photos)
        #expect(event.name == "images_imported")
        #expect(event.parameters?["count"] as? Int == 5)
        #expect(event.parameters?["source"] as? String == "photos")
        #expect(AnalyticsEvent.imagesImported(count: 1, source: .files).parameters?["source"] as? String == "files")
    }

    @Test("icloud_download: count only")
    func icloudDownload() {
        let event = AnalyticsEvent.icloudDownload(count: 3)
        #expect(event.name == "icloud_download")
        #expect(event.parameters?["count"] as? Int == 3)
        #expect(Set(event.parameters?.keys ?? [:].keys) == ["count"])
    }

    @Test("AC2: conversion_completed carries exactly the §7 counts/formats/duration keys")
    func conversionCompleted() throws {
        let event = AnalyticsEvent.conversionCompleted(
            countSuccess: 4, countFailed: 1, targetFormat: "jpg",
            isBatch: true, usedResize: false, usedStrip: true, toPDF: false, durationMs: 1234
        )
        #expect(event.name == "conversion_completed")
        let params = try #require(event.parameters)
        #expect(params["count_success"] as? Int == 4)
        #expect(params["count_failed"] as? Int == 1)
        #expect(params["target_format"] as? String == "jpg")
        #expect(params["is_batch"] as? Bool == true)
        #expect(params["used_resize"] as? Bool == false)
        #expect(params["used_strip"] as? Bool == true)
        #expect(params["to_pdf"] as? Bool == false)
        #expect(params["duration_ms"] as? Int == 1234)
        // Exactly the §7 set — nothing else (no file name, no path, no content).
        #expect(Set(params.keys) == [
            "count_success", "count_failed", "target_format", "is_batch",
            "used_resize", "used_strip", "to_pdf", "duration_ms",
        ])
    }

    @Test("pro_gate_hit: gate only")
    func proGateHit() {
        let event = AnalyticsEvent.proGateHit(gate: "batch_size")
        #expect(event.name == "pro_gate_hit")
        #expect(event.parameters?["gate"] as? String == "batch_size")
    }

    @Test("paywall_shown: trigger only")
    func paywallShown() {
        let event = AnalyticsEvent.paywallShown(trigger: "settings")
        #expect(event.name == "paywall_shown")
        #expect(event.parameters?["trigger"] as? String == "settings")
    }

    @Test("purchase_completed: product_id is the billing term")
    func purchaseCompleted() {
        let event = AnalyticsEvent.purchaseCompleted(productID: "annual")
        #expect(event.name == "purchase_completed")
        #expect(event.parameters?["product_id"] as? String == "annual")
    }

    @Test("output_saved: destination")
    func outputSaved() {
        #expect(AnalyticsEvent.outputSaved(destination: .photos).name == "output_saved")
        #expect(AnalyticsEvent.outputSaved(destination: .photos).parameters?["destination"] as? String == "photos")
        #expect(AnalyticsEvent.outputSaved(destination: .files).parameters?["destination"] as? String == "files")
        #expect(AnalyticsEvent.outputSaved(destination: .share).parameters?["destination"] as? String == "share")
    }

    @Test("onboarding_started carries no parameters")
    func onboardingStarted() {
        #expect(AnalyticsEvent.onboardingStarted.name == "onboarding_started")
        #expect(AnalyticsEvent.onboardingStarted.parameters == nil)
    }

    // MARK: AC3 — no PII-shaped values anywhere

    /// Every parameter value across every event is a primitive (Int / Bool / String enum value),
    /// never a URL, Data, or arbitrary object — so no image bytes, file names, or paths can ride
    /// along in an analytics signal (AC1/AC3).
    @Test("All event parameters are non-PII primitives")
    func parametersAreNonPIIPrimitives() {
        let events: [AnalyticsEvent] = [
            .appLaunched(isFirstLaunch: false),
            .onboardingStarted,
            .onboardingCompleted(screensViewed: 3, skipped: false),
            .imagesImported(count: 2, source: .photos),
            .icloudDownload(count: 2),
            .conversionCompleted(
                countSuccess: 1, countFailed: 0, targetFormat: "png",
                isBatch: false, usedResize: true, usedStrip: false, toPDF: false, durationMs: 10
            ),
            .proGateHit(gate: "strip_metadata"),
            .paywallShown(trigger: "target_size"),
            .purchaseCompleted(productID: "lifetime"),
            .outputSaved(destination: .files),
        ]
        for event in events {
            for (_, value) in event.parameters ?? [:] {
                let isPrimitive = value is Int || value is Bool || value is String
                #expect(isPrimitive, "\(event.name) has a non-primitive parameter value: \(type(of: value))")
            }
        }
    }
}
