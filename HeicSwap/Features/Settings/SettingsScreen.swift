//
//  SettingsScreen.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 23/02/2026.
//

import StoreKit
import SwiftUI

/// The grouped Settings screen (task 8.1), pushed onto the Convert stack from the nav bar.
///
/// Four sections: **Conversion defaults** (format / quality / strip, persisted via
/// `ConversionDefaults` and mirrored into the Convert screen's live options — AC1); **HeicSwap Pro**
/// (status, Restore — AC2, and a manage-subscription link); **Privacy** (the literally-true
/// statement — AC3); and **About** (rate, contact, Terms, version). Intentionally owns no
/// `NavigationStack` — it's a pushed destination, so the host stack supplies the bar and back button.
struct SettingsScreen: View {
    @Environment(\.entitlementStore) private var entitlementStore
    @Environment(\.conversionDefaults) private var conversionDefaults
    @Environment(\.requestReview) private var requestReview

    @State private var isPaywallPresented = false
    @State private var restoreState: RestoreState = .idle

    /// The Restore button's lifecycle: idle, in-flight, or showing the result of the last attempt.
    private enum RestoreState: Equatable {
        case idle
        case restoring
        case message(String)
    }

    /// Manage subscriptions in the App Store (per the task: via the App Store URL, not a StoreKit
    /// sheet). A real, always-resolving Apple URL.
    private static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")
    /// Support contact — a placeholder address on the app's domain (like the placeholder privacy URL)
    /// until the real inbox is set up at submission (task 11.1).
    private static let supportURL = URL(string: "mailto:support@heicswap.app")

    var body: some View {
        List {
            DefaultsSection(
                defaults: conversionDefaults,
                isPro: entitlementStore.isPro,
                onProLockTapped: { isPaywallPresented = true }
            )
            subscriptionSection
            privacySection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .sheet(isPresented: $isPaywallPresented) {
            PaywallSheet()
        }
    }

    // MARK: - Subscription

    @ViewBuilder private var subscriptionSection: some View {
        Section {
            if entitlementStore.isPro {
                Label {
                    Text("HeicSwap Pro is active")
                        .foregroundStyle(Theme.Colors.textPrimary)
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.Colors.success)
                }

                if let manageURL = Self.manageSubscriptionsURL {
                    Link(destination: manageURL) {
                        settingsLabel("Manage Subscription", systemImage: "creditcard")
                    }
                    .accessibilityHint(Text(String(localized: "Opens your subscriptions in the App Store")))
                }
            } else {
                Button {
                    isPaywallPresented = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                            Text("Unlock HeicSwap Pro")
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("Unlimited batches, resize to size, strip metadata")
                                .font(Theme.Typography.footnote)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "lock.open.fill")
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
                .accessibilityHint(Text(String(localized: "Opens the HeicSwap Pro paywall")))
            }

            restoreButton

            if case let .message(text) = restoreState {
                Text(text)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        } header: {
            sectionHeader("HeicSwap Pro")
        }
        .listRowBackground(Theme.Colors.surface)
    }

    private var restoreButton: some View {
        Button(action: restore) {
            HStack(spacing: Theme.Spacing.item) {
                settingsLabel("Restore Purchases", systemImage: "arrow.clockwise")
                if restoreState == .restoring {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(restoreState == .restoring)
        .accessibilityHint(Text(String(localized: "Re-syncs purchases you've already made")))
    }

    /// Re-syncs entitlements with the store (AC2) and reports the result inline. A genuine failure is
    /// surfaced; "nothing to restore" is a normal, non-error outcome.
    private func restore() {
        guard restoreState != .restoring else { return }
        restoreState = .restoring
        Task {
            do {
                try await entitlementStore.restore()
                restoreState = .message(
                    entitlementStore.isPro
                        ? String(localized: "Purchases restored. HeicSwap Pro is active.")
                        : String(localized: "No purchases to restore.")
                )
            } catch {
                restoreState = .message(String(localized: "Couldn’t restore purchases. Please try again."))
            }
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.item) {
                Text(PrivacyStatement.headline)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(PrivacyStatement.points) { point in
                    Label {
                        Text(point.text)
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: point.systemImage)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }

                if let privacyURL = LegalLinks.privacyPolicy {
                    Link(destination: privacyURL) {
                        Text("Read the full privacy policy")
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .padding(.top, Theme.Spacing.tight)
                }
            }
            .padding(.vertical, Theme.Spacing.tight)
            .accessibilityElement(children: .combine)
        } header: {
            sectionHeader("Privacy")
        }
        .listRowBackground(Theme.Colors.surface)
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            Button {
                requestReview()
            } label: {
                settingsLabel("Rate HeicSwap", systemImage: "star")
            }

            if let supportURL = Self.supportURL {
                Link(destination: supportURL) {
                    settingsLabel("Contact Support", systemImage: "envelope")
                }
            }

            if let termsURL = LegalLinks.termsOfUse {
                Link(destination: termsURL) {
                    settingsLabel("Terms of Use", systemImage: "doc.text")
                }
            }
        } header: {
            sectionHeader("About")
        } footer: {
            Text(versionText)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, Theme.Spacing.small)
        }
        .listRowBackground(Theme.Colors.surface)
    }

    /// "HeicSwap 1.0 (1)" from the bundle — a quiet build stamp for support and bug reports.
    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return String(localized: "HeicSwap \(version) (\(build))")
    }

    // MARK: - Shared

    /// A settings row label — amber icon over primary text, matching the Warm Darkroom interactive
    /// language used across the app.
    private func settingsLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(title).foregroundStyle(Theme.Colors.textPrimary)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(Theme.Colors.accent)
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(Theme.Typography.footnote)
            .foregroundStyle(Theme.Colors.textSecondary)
    }
}

// MARK: - Defaults section

/// The conversion-defaults section: format, quality (lossy formats only), and metadata stripping.
/// Bound to the persisted `ConversionDefaults`; the Convert screen mirrors changes here into its live
/// session options (AC1). Strip is a Pro feature, so it's gated for free users exactly like the
/// Options sheet — a locked row that opens the paywall rather than toggling.
private struct DefaultsSection: View {
    @Bindable var defaults: ConversionDefaults
    let isPro: Bool
    let onProLockTapped: () -> Void

    var body: some View {
        Section {
            formatRow
            if defaults.format.usesQuality {
                qualityRow
            }
            stripRow
        } header: {
            Text("Conversion defaults")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
        } footer: {
            Text("Used as the starting point each time you open Options.")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .listRowBackground(Theme.Colors.surface)
    }

    private var formatRow: some View {
        Picker(selection: $defaults.format) {
            ForEach(OutputFormat.allCases) { format in
                Text(format.displayName).tag(format)
            }
        } label: {
            Text("Format").foregroundStyle(Theme.Colors.textPrimary)
        }
        .pickerStyle(.menu)
        .tint(Theme.Colors.accent)
        .accessibilityLabel(Text(String(localized: "Default format")))
    }

    private var qualityRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                Text("Quality")
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text(OptionsSummary.qualityText(defaults.quality))
                    .font(Theme.Typography.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Slider(value: $defaults.quality, in: 0.1...1.0, step: 0.05)
                .tint(Theme.Colors.accent)
                .accessibilityLabel(Text(String(localized: "Default quality")))
                .accessibilityValue(Text(OptionsSummary.qualityText(defaults.quality)))
        }
        .padding(.vertical, Theme.Spacing.tight)
    }

    @ViewBuilder private var stripRow: some View {
        if isPro {
            Toggle(isOn: $defaults.stripsMetadata) {
                stripLabel
            }
            .tint(Theme.Colors.accent)
        } else {
            // Locked: tapping routes to the paywall (like the Options sheet) rather than toggling.
            Button(action: onProLockTapped) {
                HStack {
                    stripLabel
                    Spacer()
                    ProLockBadge()
                }
                .contentShape(Rectangle())
            }
            .accessibilityHint(Text(String(localized: "Pro feature")))
        }
    }

    private var stripLabel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text("Strip metadata")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Remove EXIF and GPS location from every photo")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Previews

@MainActor private func previewStore(isPro: Bool) -> EntitlementStore {
    // Seed the offline cache so the store reports Pro synchronously at init — previews never call
    // `refresh()`, which is where the live client's entitlement would otherwise land.
    let cache = EntitlementCache(defaults: UserDefaults(suiteName: "SettingsPreview-\(isPro)")!)
    cache.store(isPro ? .pro : .free)
    return EntitlementStore(purchaseClient: StubPurchaseClient(isPro: isPro), cache: cache)
}

#Preview("Free — Light") {
    NavigationStack {
        SettingsScreen()
            .environment(\.entitlementStore, previewStore(isPro: false))
    }
    .preferredColorScheme(.light)
}

#Preview("Free — Dark") {
    NavigationStack {
        SettingsScreen()
            .environment(\.entitlementStore, previewStore(isPro: false))
    }
    .preferredColorScheme(.dark)
}

#Preview("Pro") {
    NavigationStack {
        SettingsScreen()
            .environment(\.entitlementStore, previewStore(isPro: true))
    }
}
