//
//  PrivacyStatementTests.swift
//  HeicSwapTests
//
//  The Settings privacy statement (task 8.1, AC3): it must be precisely true to what HeicSwap does
//  and must not overclaim. These pin the content contract — the on-device promise, the disclosed
//  analytics, and the absence of a false "no network at all" claim — the same way `OnboardingContent`
//  tests pin the onboarding copy. The rendered section is verified manually (Dark Mode / VoiceOver).
//

import Foundation
import Testing
@testable import HeicSwap

@MainActor
struct PrivacyStatementTests {

    /// All statement copy joined, for substring assertions.
    private var allCopy: String {
        ([PrivacyStatement.headline] + PrivacyStatement.points.map(\.text))
            .joined(separator: " ")
    }

    @Test("Every privacy point has copy and a symbol")
    func everyPointHasContent() {
        #expect(!PrivacyStatement.headline.isEmpty)
        #expect(!PrivacyStatement.points.isEmpty)
        for point in PrivacyStatement.points {
            #expect(!point.text.isEmpty)
            #expect(!point.systemImage.isEmpty)
        }
    }

    @Test("Point ids are unique and zero-based in order")
    func pointIDsAreSequential() {
        #expect(PrivacyStatement.points.map(\.id) == Array(0..<PrivacyStatement.points.count))
    }

    @Test("It makes the on-device, never-uploaded promise")
    func statesOnDevicePromise() {
        let copy = allCopy.lowercased()
        #expect(copy.contains("on your device") || copy.contains("on your iphone"))
        #expect(copy.contains("never") && (copy.contains("uploaded") || copy.contains("leave")))
    }

    @Test("It discloses anonymous usage statistics rather than claiming nothing is collected")
    func disclosesAnonymousAnalytics() {
        let copy = allCopy.lowercased()
        #expect(copy.contains("anonymous"))
        #expect(copy.contains("usage"))
    }

    @Test("It does not overclaim a blanket 'no network' / 'no internet' guarantee")
    func doesNotOverclaimNoNetwork() {
        // HeicSwap *does* make narrow analytics + purchase-validation calls, so a blanket "no
        // internet / no network connections" claim would be false. Guard against that overclaim.
        let copy = allCopy.lowercased()
        #expect(!copy.contains("no internet"))
        #expect(!copy.contains("no network"))
        #expect(!copy.contains("never connects"))
    }
}
