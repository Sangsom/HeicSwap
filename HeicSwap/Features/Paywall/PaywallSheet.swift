//
//  PaywallSheet.swift
//  HeicSwap
//
//  The HeicSwap Pro paywall (task 6.2): a custom Warm Darkroom sheet — on-device badge, honest
//  benefits, the annual plan highlighted by default, weekly + lifetime as secondary options, and
//  Restore + Terms/Privacy. No countdowns, no pre-selected weekly, no nag on dismiss.
//
//  Prices come from the store via `EntitlementStore` (task 6.1); the screen never hardcodes them.
//  Presentation triggers (the value-gated Pro actions) are wired in task 6.3 — this builds the
//  screen and gives it a permanent home in Settings.
//

import SwiftUI

/// The HeicSwap Pro paywall, presented as a large sheet.
///
/// Binds to the app-wide `EntitlementStore`: it loads the purchasable products, highlights the
/// annual plan by default (AC1), and on Continue/Restore applies the resulting entitlement through
/// the store (AC2). Dismissing returns the user to the free tier with no further prompt (AC3).
struct PaywallSheet: View {

    /// What opened the paywall, reported as `paywall_shown`'s `trigger` (PRD §7): a value-gate
    /// kind (`batch_size` / `target_size` / `strip_metadata`) or `settings` for the permanent entry.
    let trigger: String

    @Environment(\.entitlementStore) private var store
    @Environment(\.analyticsClient) private var analytics
    @Environment(\.dismiss) private var dismiss

    /// The currently highlighted plan. Seeded to the annual plan once products load (AC1).
    @State private var selectedProductID: String?
    /// Ensures `paywall_shown` is logged exactly once per presentation.
    @State private var didLogShown = false
    /// The in-flight store action, so the matching control shows progress and both are disabled.
    @State private var action: Action?
    /// A user-facing message for a failed purchase/restore (cancellation is silent, not an error).
    @State private var message: String?

    private enum Action: Equatable { case purchasing, restoring }

    /// The four honest things Pro unlocks, matching the value gate (`ValueGate`): batches beyond the
    /// free limit, target-file-size resize, and metadata stripping. No promises of unbuilt features.
    private static let benefits: [LocalizedStringKey] = [
        "Convert unlimited photos at once",
        "Combine any number of photos into one PDF",
        "Resize to an exact file size",
        "Strip EXIF & GPS location from every photo",
    ]

    private var plans: [PaywallPlan] { PaywallPlan.plans(from: store.products) }
    private var selectedPlan: PaywallPlan? { plans.first { $0.id == selectedProductID } }
    private var isBusy: Bool { action != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.sectionGap) {
                closeRow
                headerSection
                benefitsSection
                plansSection
                if let message {
                    messageBanner(message)
                }
                continueButton
                legalFooter
            }
            .padding(.horizontal, Theme.Spacing.section)
            .padding(.bottom, Theme.Spacing.majorBreak)
        }
        .background(Theme.Colors.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            if !didLogShown {
                didLogShown = true
                analytics.log(.paywallShown(trigger: trigger))
            }
            await store.loadProducts()
            if selectedProductID == nil {
                selectedProductID = PaywallPlan.defaultSelectionID(in: store.products)
            }
        }
    }

    // MARK: Close

    private var closeRow: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(String(localized: "Close")))
        }
        .padding(.top, Theme.Spacing.small)
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.item) {
            OnDeviceBadge()

            Text("HeicSwap Pro")
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Unlimited conversions and pro tools — all on your iPhone, never uploaded.")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Benefits

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.item) {
            ForEach(Self.benefits.indices, id: \.self) { index in
                Label {
                    Text(Self.benefits[index])
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Plans

    @ViewBuilder private var plansSection: some View {
        if plans.isEmpty {
            Text("Subscriptions are unavailable right now. Check your connection and try again.")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.item)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.input)
                        .fill(Theme.Colors.surface)
                }
        } else {
            VStack(spacing: Theme.Spacing.item) {
                ForEach(plans) { plan in
                    PlanRow(plan: plan, isSelected: plan.id == selectedProductID) {
                        selectedProductID = plan.id
                    }
                    .disabled(isBusy)
                }
            }
        }
    }

    // MARK: Continue

    private var continueButton: some View {
        Button(action: purchaseSelected) {
            Group {
                if action == .purchasing {
                    ProgressView()
                        .tint(Theme.Colors.onAccent)
                } else {
                    Text("Continue")
                        .font(Theme.Typography.headline)
                }
            }
            .foregroundStyle(Theme.Colors.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.item)
            .background(Theme.Colors.accent.opacity(canContinue ? 1 : 0.4), in: Capsule())
        }
        .disabled(!canContinue)
        .accessibilityLabel(Text(String(localized: "Continue")))
        .accessibilityHint(Text(String(localized: "Subscribe to the selected plan")))
    }

    private var canContinue: Bool { selectedPlan != nil && !isBusy }

    // MARK: Legal footer

    private var legalFooter: some View {
        VStack(spacing: Theme.Spacing.small) {
            HStack(spacing: Theme.Spacing.item) {
                Button(action: restore) {
                    if action == .restoring {
                        ProgressView()
                    } else {
                        Text("Restore")
                    }
                }
                .disabled(isBusy)
                .accessibilityLabel(Text(String(localized: "Restore purchases")))

                if let terms = LegalLinks.termsOfUse {
                    separatorDot
                    Link("Terms", destination: terms)
                }
                if let privacy = LegalLinks.privacyPolicy {
                    separatorDot
                    Link("Privacy", destination: privacy)
                }
            }
            .font(Theme.Typography.footnote)
            .foregroundStyle(Theme.Colors.accent)

            Text("Cancel anytime. No fake timers, no tricks.")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var separatorDot: some View {
        Text(verbatim: "·").foregroundStyle(Theme.Colors.textSecondary)
    }

    private func messageBanner(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.subheadline)
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.item)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.input)
                    .fill(Theme.Colors.surface2)
            }
            .transition(.opacity)
    }

    // MARK: Actions

    /// Buys the highlighted plan and, on a Pro-granting purchase, dismisses — Pro turns on the moment
    /// the store reports it (AC2). User cancellation is silent; a genuine failure shows a message.
    private func purchaseSelected() {
        guard let plan = selectedPlan, !isBusy else { return }
        action = .purchasing
        message = nil
        Task {
            defer { action = nil }
            do {
                let outcome = try await store.purchase(plan.product)
                if case .purchased(let isPro) = outcome {
                    analytics.log(.purchaseCompleted(productID: Self.productID(for: plan.product.term)))
                    if isPro { dismiss() }
                }
            } catch {
                message = String(localized: "Couldn’t complete the purchase. Please try again.")
            }
        }
    }

    /// Re-syncs entitlements with the store (AC2). Dismisses if Pro is restored; otherwise tells the
    /// user there was nothing to restore.
    private func restore() {
        guard !isBusy else { return }
        action = .restoring
        message = nil
        Task {
            defer { action = nil }
            do {
                try await store.restore()
                if store.isPro {
                    dismiss()
                } else {
                    message = String(localized: "No purchases to restore.")
                }
            } catch {
                message = String(localized: "Couldn’t restore purchases. Please try again.")
            }
        }
    }

    /// The `product_id` value for `purchase_completed` — the billing term (`annual` / `weekly` /
    /// `lifetime`), per PRD §7, rather than the raw store SKU.
    private static func productID(for term: PurchaseProduct.Term) -> String {
        switch term {
        case .annual: "annual"
        case .weekly: "weekly"
        case .lifetime: "lifetime"
        }
    }
}

// MARK: - Plan row

/// A single selectable plan card: title, per-term price, and an amber "Best value" tag on the
/// annual plan. The selected row is outlined and tinted amber; tapping selects it.
private struct PlanRow: View {
    let plan: PaywallPlan
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Theme.Spacing.item) {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    HStack(spacing: Theme.Spacing.small) {
                        Text(plan.title)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if plan.isBestValue {
                            bestValueTag
                        }
                    }
                    Text(plan.priceDetail)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.section)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.input)
                    .fill(isSelected ? Theme.Colors.accent.opacity(0.10) : Theme.Colors.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.input)
                    .strokeBorder(
                        isSelected ? Theme.Colors.accent : Theme.Colors.separator,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint(Text(String(localized: "Selects this plan")))
    }

    private var bestValueTag: some View {
        Text("Best value")
            .font(Theme.Typography.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Theme.Colors.onAccent)
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, Theme.Spacing.tight)
            .background(Theme.Colors.accent, in: Capsule())
    }

    private var accessibilityLabel: String {
        let base = "\(plan.title), \(plan.priceDetail)"
        return plan.isBestValue ? String(localized: "\(base), best value") : base
    }
}

// MARK: - Previews

/// A store seeded with the three SKUs so previews render the full paywall without a network/sandbox.
@MainActor private func previewStore(isPro: Bool = false) -> EntitlementStore {
    let products = [
        PurchaseProduct(id: "pro.annual", term: .annual, displayName: "Pro Annual", localizedPrice: "$9.99", price: 9.99),
        PurchaseProduct(id: "pro.weekly", term: .weekly, displayName: "Pro Weekly", localizedPrice: "$1.99", price: 1.99),
        PurchaseProduct(id: "pro.lifetime", term: .lifetime, displayName: "Pro Lifetime", localizedPrice: "$19.99", price: 19.99),
    ]
    return EntitlementStore(purchaseClient: StubPurchaseClient(isPro: isPro, products: products))
}

#Preview("Light") {
    PaywallSheet(trigger: "preview")
        .environment(\.entitlementStore, previewStore())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    PaywallSheet(trigger: "preview")
        .environment(\.entitlementStore, previewStore())
        .preferredColorScheme(.dark)
}
