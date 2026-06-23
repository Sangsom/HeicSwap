//
//  LegalLinks.swift
//  HeicSwap
//
//  The legal URLs the paywall links to (and, later, Settings — task 8.1). Subscriptions require a
//  Terms (EULA) and a Privacy Policy link, so they live here in one place rather than inline.
//

import Foundation

/// Canonical legal URLs surfaced by the paywall.
///
/// `termsOfUse` points at Apple's Standard License Agreement — the EULA every StoreKit app may
/// reference, and a real, always-resolving URL. `privacyPolicy` is a placeholder until the hosted
/// policy page is produced at submission (task 11.1); swap it for the real URL before release.
/// Both are optional so a malformed string can never force-unwrap-crash — the footer only renders
/// links that resolve.
enum LegalLinks {

    /// Apple's Standard License Agreement (EULA).
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")

    /// Placeholder privacy policy — replace with the hosted page before submission (task 11.1).
    static let privacyPolicy = URL(string: "https://heicswap.app/privacy")
}
