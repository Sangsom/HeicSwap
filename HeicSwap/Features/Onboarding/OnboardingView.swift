//
//  OnboardingView.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 22/06/2026.
//

import SwiftUI

/// The ≤60-second first run (task 7.1): three skippable, paged screens that sell the value and the
/// privacy promise, then hand off to the Convert empty state underneath.
///
/// Presented once as a `fullScreenCover` from `RootView`; completing or skipping sets the
/// `hasOnboarded` flag, which dismisses the cover and reveals the (already-loaded) empty state — so
/// onboarding "ends on the empty state" with no extra navigation. No account, no paywall here.
///
/// On photo permission: import is deliberately permission-free (the picker scopes access to the
/// items the user taps), and the only Photos permission the app ever requests is **add-only**, at
/// the moment of saving a result — never up front. So this flow asks for nothing; the final screen
/// simply invites the user into the picker that lives on the empty state.
struct OnboardingView: View {
    @AppStorage(Onboarding.hasOnboardedKey) private var hasOnboarded = false
    @Environment(\.analyticsClient) private var analyticsClient

    @State private var selection = 0
    @State private var didLogStart = false
    /// The furthest page the user has reached, so `onboarding_completed` can report how many
    /// screens they actually saw (PRD §7 `screens_viewed`).
    @State private var maxPageReached = 0

    private var isLastPage: Bool { selection == Onboarding.pages.count - 1 }

    var body: some View {
        ZStack {
            Theme.Colors.background
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.sectionGap) {
                header

                TabView(selection: $selection) {
                    ForEach(Onboarding.pages) { page in
                        OnboardingPageView(page: page)
                            .tag(page.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: selection) { _, page in
                    maxPageReached = max(maxPageReached, page)
                }

                PageIndicator(count: Onboarding.pages.count, selection: selection)

                OnboardingCTAButton(title: ctaTitle, action: advance)
                    .padding(.horizontal, Theme.Spacing.section)
            }
            .padding(.vertical, Theme.Spacing.section)
        }
        .onAppear {
            guard !didLogStart else { return }
            didLogStart = true
            analyticsClient.log(.onboardingStarted)
        }
    }

    private var header: some View {
        HStack {
            OnDeviceBadge()
            Spacer()
            Button { finish(skipped: true) } label: {
                Text("Skip")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .accessibilityHint(Text(String(localized: "Skips onboarding and opens the app")))
        }
        .padding(.horizontal, Theme.Spacing.section)
    }

    private var ctaTitle: String {
        isLastPage
            ? String(localized: "Start converting")
            : String(localized: "Continue")
    }

    /// Advances to the next screen, or completes onboarding on the last one.
    private func advance() {
        if isLastPage {
            finish(skipped: false)
        } else {
            withAnimation(.snappy) { selection += 1 }
        }
    }

    /// Records onboarding as seen (AC3) and dismisses the cover — the empty state is already behind
    /// it — after logging `onboarding_completed` with how many screens were seen and whether the
    /// user skipped (PRD §7).
    private func finish(skipped: Bool) {
        analyticsClient.log(.onboardingCompleted(screensViewed: maxPageReached + 1, skipped: skipped))
        hasOnboarded = true
    }
}

// MARK: - Page

/// A single onboarding screen: an accent-glow symbol, a serif value line, and supporting copy.
/// Wrapped in a centering `ScrollView` so the largest Dynamic Type sizes scroll instead of clipping.
private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Theme.Spacing.sectionGap) {
                    Image(systemName: page.systemImage)
                        .font(.system(size: 72, weight: .regular))
                        .foregroundStyle(Theme.Gradients.safelight)
                        .accessibilityHidden(true)

                    VStack(spacing: Theme.Spacing.item) {
                        Text(page.headline)
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .multilineTextAlignment(.center)

                        Text(page.body)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Spacing.sectionGap)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Page indicator

/// A custom paging indicator — the active page is a wider amber capsule, the rest hairline dots.
/// Hidden from VoiceOver, which reads the page content directly as the user swipes.
private struct PageIndicator: View {
    let count: Int
    let selection: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == selection ? Theme.Colors.accent : Theme.Colors.separator)
                    .frame(width: index == selection ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy, value: selection)
        .accessibilityHidden(true)
    }
}

// MARK: - CTA

/// The full-width amber capsule that advances the flow — dark ink on safelight amber, matching the
/// Convert CTA so the primary action reads the same everywhere.
private struct OnboardingCTAButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.item)
                .background(Theme.Colors.accent, in: Capsule())
        }
        .accessibilityLabel(Text(title))
    }
}

#Preview("Light") {
    OnboardingView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    OnboardingView()
        .preferredColorScheme(.dark)
}
