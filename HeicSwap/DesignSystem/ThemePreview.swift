//
//  ThemePreview.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 23/02/2026.
//
//  A living style guide for the Warm Darkroom design system. Debug-only —
//  it ships in no build, it exists purely to verify tokens in Xcode previews
//  (toggle Light/Dark, crank Dynamic Type) and as documentation of the system.
//

#if DEBUG
import SwiftUI

/// Renders every Warm Darkroom token — colors, type scale, the amber CTA, and
/// the safelight gradient — so the whole system can be eyeballed at once.
private struct ThemePreview: View {

    private struct Swatch: Identifiable {
        let id = UUID()
        let name: String
        let color: Color
    }

    private let swatches: [Swatch] = [
        .init(name: "background", color: Theme.Colors.background),
        .init(name: "surface", color: Theme.Colors.surface),
        .init(name: "surface2", color: Theme.Colors.surface2),
        .init(name: "textPrimary", color: Theme.Colors.textPrimary),
        .init(name: "textSecondary", color: Theme.Colors.textSecondary),
        .init(name: "accent", color: Theme.Colors.accent),
        .init(name: "accent2", color: Theme.Colors.accent2),
        .init(name: "success", color: Theme.Colors.success),
        .init(name: "destructive", color: Theme.Colors.destructive),
        .init(name: "separator", color: Theme.Colors.separator)
    ]

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: Theme.Spacing.item)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.sectionGap) {
                typeScale
                colorGrid
                callToAction
                safelight
            }
            .padding(Theme.Spacing.section)
        }
        .background(Theme.Colors.background)
        .foregroundStyle(Theme.Colors.textPrimary)
    }

    private var typeScale: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("Convert").font(Theme.Typography.largeTitle)
            Text("Keep every photo on your device").font(Theme.Typography.title2)
            Text("HEIC").font(Theme.Typography.headline)
            Text("Primary content uses the system sans for legibility.")
                .font(Theme.Typography.body)
            Text("10 free conversions left today")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var colorGrid: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.item) {
            ForEach(swatches) { swatch in
                VStack(spacing: Theme.Spacing.tight) {
                    RoundedRectangle(cornerRadius: Theme.Radius.thumbnail)
                        .fill(swatch.color)
                        .frame(height: 56)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.thumbnail)
                                .stroke(Theme.Colors.separator, lineWidth: 1)
                        )
                    Text(swatch.name)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    /// Demonstrates the CTA contrast rule: dark ink on amber, never white.
    private var callToAction: some View {
        Text("Convert 5 photos")
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.item)
            .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
    }

    private var safelight: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card)
            .fill(Theme.Gradients.safelight)
            .frame(height: 80)
            .overlay(
                Text("Safelight gradient")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.onAccent)
            )
    }
}

#Preview("Tokens — Light") {
    ThemePreview()
        .preferredColorScheme(.light)
}

#Preview("Tokens — Dark") {
    ThemePreview()
        .preferredColorScheme(.dark)
}

#Preview("Tokens — XXL type") {
    ThemePreview()
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
