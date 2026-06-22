//
//  OnboardingContentTests.swift
//  HeicSwapTests
//
//  The pure onboarding content (task 7.1): at most three screens, in the value → privacy → add-photos
//  order, with the privacy screen stating the "never uploaded" promise. The flow itself — paging,
//  Skip, the persisted shows-once flag, Dark Mode / Dynamic Type — is verified manually; these cover
//  the content contract the screens render.
//

import Foundation
import Testing
@testable import HeicSwap

@MainActor
struct OnboardingContentTests {

    @Test("There are at most three onboarding screens")
    func atMostThreePages() {
        #expect(Onboarding.pages.count <= 3)
        #expect(!Onboarding.pages.isEmpty)
    }

    @Test("Page ids are unique and zero-based in order, matching TabView tags")
    func pageIDsAreSequential() {
        #expect(Onboarding.pages.map(\.id) == Array(0..<Onboarding.pages.count))
    }

    @Test("Every screen has a non-empty headline, body, and symbol")
    func everyPageHasCopy() {
        for page in Onboarding.pages {
            #expect(!page.headline.isEmpty)
            #expect(!page.body.isEmpty)
            #expect(!page.systemImage.isEmpty)
        }
    }

    @Test("A privacy screen states the photos are never uploaded")
    func privacyScreenStatesNeverUploaded() {
        let statesPromise = Onboarding.pages.contains { page in
            "\(page.headline) \(page.body)".localizedCaseInsensitiveContains("never uploaded")
        }
        #expect(statesPromise)
    }

    @Test("The final screen invites the user to add photos")
    func finalScreenIsAddPhotos() {
        let last = Onboarding.pages.last
        #expect(last?.systemImage == "photo.badge.plus")
    }

    @Test("The persistence key is stable so the shows-once flag survives launches")
    func hasOnboardedKeyIsStable() {
        #expect(Onboarding.hasOnboardedKey == "hasOnboarded")
    }
}
