//
//  OnDeviceBadge.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 21/06/2026.
//

import SwiftUI

/// The persistent "On-device" trust badge.
///
/// HeicSwap's core promise is that photos are processed entirely on the device and
/// never uploaded. This badge surfaces that promise wherever conversion happens —
/// the Convert screen, the "developing" reveal, results, and the paywall (PRD §5).
/// Kept as one reusable view so the wording and styling stay identical everywhere.
struct OnDeviceBadge: View {
    /// Liquid Glass needs to be turned off when the user asks for less transparency — fall back to
    /// the solid `surface2` capsule the badge has always used, so the amber label never loses contrast.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        capsule
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(String(localized: "On-device. Your photos never leave this iPhone.")))
    }

    /// The badge over its backing: a Liquid Glass capsule (task 10.2) so the recurring trust chrome
    /// reads as a floating pill on iOS 26, or the original solid `surface2` capsule when Reduce
    /// Transparency is on — keeping the amber label's contrast guaranteed.
    @ViewBuilder private var capsule: some View {
        if reduceTransparency {
            label.background(Theme.Colors.surface2, in: Capsule())
        } else {
            label.glassEffect(in: Capsule())
        }
    }

    private var label: some View {
        HStack(spacing: Theme.Spacing.tight) {
            Image(systemName: "lock.shield.fill")
            Text("On-device")
        }
        .font(Theme.Typography.caption)
        .fontWeight(.semibold)
        .foregroundStyle(Theme.Colors.accent)
        .padding(.horizontal, Theme.Spacing.item)
        .padding(.vertical, Theme.Spacing.small)
    }
}

#Preview("Light") {
    OnDeviceBadge()
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    OnDeviceBadge()
        .padding()
        .preferredColorScheme(.dark)
}
