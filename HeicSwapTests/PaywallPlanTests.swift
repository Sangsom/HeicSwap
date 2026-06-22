//
//  PaywallPlanTests.swift
//  HeicSwapTests
//
//  The pure presentation logic behind the paywall (task 6.2): products project to ordered,
//  titled, priced rows; the annual plan is flagged best value and chosen as the default highlight
//  (AC1). The sheet itself — Restore, dismiss, Dark Mode / VoiceOver / Dynamic Type — is verified
//  manually; these cover the ordering and default-selection logic it relies on.
//

import Foundation
import Testing
@testable import HeicSwap

/// The three SKUs HeicSwap sells, deliberately out of display order so sorting is exercised.
/// File-scope (not a MainActor-isolated static member) so the synchronous tests touch it freely.
private let paywallTestProducts = [
    PurchaseProduct(id: "pro.lifetime", term: .lifetime, displayName: "Pro Lifetime", localizedPrice: "$19.99", price: 19.99),
    PurchaseProduct(id: "pro.weekly", term: .weekly, displayName: "Pro Weekly", localizedPrice: "$1.99", price: 1.99),
    PurchaseProduct(id: "pro.annual", term: .annual, displayName: "Pro Annual", localizedPrice: "$9.99", price: 9.99),
]

@MainActor
struct PaywallPlanTests {

    @Test("Plans are ordered annual, then weekly, then lifetime")
    func plansAreOrdered() {
        let plans = PaywallPlan.plans(from: paywallTestProducts)
        #expect(plans.map(\.id) == ["pro.annual", "pro.weekly", "pro.lifetime"])
    }

    @Test("AC1: the annual plan is the default highlight")
    func annualIsDefaultSelection() {
        #expect(PaywallPlan.defaultSelectionID(in: paywallTestProducts) == "pro.annual")
    }

    @Test("AC1: only the annual plan is flagged best value")
    func onlyAnnualIsBestValue() {
        let plans = PaywallPlan.plans(from: paywallTestProducts)
        let bestValueIDs = plans.filter(\.isBestValue).map(\.id)
        #expect(bestValueIDs == ["pro.annual"])
    }

    @Test("Each term projects to its plain-language title")
    func titlesPerTerm() {
        let byID = Dictionary(uniqueKeysWithValues: PaywallPlan.plans(from: paywallTestProducts).map { ($0.id, $0) })
        #expect(byID["pro.annual"]?.title == "Yearly")
        #expect(byID["pro.weekly"]?.title == "Weekly")
        #expect(byID["pro.lifetime"]?.title == "Lifetime")
    }

    @Test("Price detail uses the store's localized price plus an honest period suffix")
    func priceDetailPerTerm() {
        let byID = Dictionary(uniqueKeysWithValues: PaywallPlan.plans(from: paywallTestProducts).map { ($0.id, $0) })
        #expect(byID["pro.annual"]?.priceDetail == "$9.99 / year")
        #expect(byID["pro.weekly"]?.priceDetail == "$1.99 / week")
        #expect(byID["pro.lifetime"]?.priceDetail == "$19.99 one-time")
    }

    @Test("With no annual plan the default falls back to the first listed plan")
    func defaultFallsBackWithoutAnnual() {
        let noAnnual = paywallTestProducts.filter { $0.term != .annual }
        // Ordered, the first non-annual plan is weekly.
        #expect(PaywallPlan.defaultSelectionID(in: noAnnual) == "pro.weekly")
    }

    @Test("Empty products yield no plans and no default selection")
    func emptyProducts() {
        #expect(PaywallPlan.plans(from: []).isEmpty)
        #expect(PaywallPlan.defaultSelectionID(in: []) == nil)
    }
}
