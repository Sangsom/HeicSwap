//
//  ProLockBadge.swift
//  HeicSwap
//
//  The amber "Pro" lock affordance shown on entitlement-gated controls.
//

import SwiftUI

/// The amber lock that marks a Pro-gated control for free users.
///
/// HeicSwap gates a few advanced options — resize-to-target-size and metadata stripping — behind
/// Pro (PRD §6 / `ValueGate`). This badge flags those controls; the control it sits on routes to
/// the paywall (task 6.2) instead of acting. One reusable view keeps the lock wording and styling
/// identical everywhere it appears.
struct ProLockBadge: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            Image(systemName: "lock.fill")
            Text(verbatim: "PRO")
        }
        .font(Theme.Typography.caption)
        .fontWeight(.semibold)
        .foregroundStyle(Theme.Colors.onAccent)
        .padding(.horizontal, Theme.Spacing.small)
        .padding(.vertical, Theme.Spacing.tight)
        .background(Theme.Colors.accent, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Pro feature")))
    }
}

#Preview("Light") {
    ProLockBadge()
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ProLockBadge()
        .padding()
        .preferredColorScheme(.dark)
}
