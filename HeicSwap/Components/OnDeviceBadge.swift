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
    var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            Image(systemName: "lock.shield.fill")
            Text("On-device")
        }
        .font(Theme.Typography.caption)
        .fontWeight(.semibold)
        .foregroundStyle(Theme.Colors.accent)
        .padding(.horizontal, Theme.Spacing.item)
        .padding(.vertical, Theme.Spacing.small)
        .background(Theme.Colors.surface2, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(localized: "On-device. Your photos never leave this iPhone.")))
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
