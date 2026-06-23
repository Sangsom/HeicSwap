//
//  ConversionOptionsSheet.swift
//  HeicSwap
//
//  The Options sheet (task 5.2): pick target format, quality, resize, and metadata stripping for
//  the next conversion. Presented at the `.medium` detent from the Convert screen's options row.
//

import SwiftUI

/// Where the user chooses what to produce: target format, quality, resize, and whether to strip
/// metadata.
///
/// Binds straight to the screen's shared `ConversionOptions`, so selections persist as session
/// defaults across presentations. Advanced choices — resize-to-target-size and metadata
/// stripping — are gated behind Pro for free users (PRD §6 / `ValueGate`); the gate shows an amber
/// lock and routes to the paywall (task 6.2) via `onProLockTapped` instead of acting. Entitlement
/// is read as a plain value, stubbed `.free` until the entitlement client lands (task 6.1).
struct ConversionOptionsSheet: View {
    @Binding var options: ConversionOptions
    let entitlement: Entitlement
    /// Invoked when a free user taps a Pro-gated control, carrying the specific gate they hit so the
    /// paywall (task 6.3) can record the trigger and resume the action after an upgrade.
    var onProLockTapped: (ValueGate.Trigger) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    /// Remembered pixel cap / byte target, so toggling resize modes during one sheet session keeps
    /// a sensible value instead of resetting. Seeded from the incoming options.
    @State private var pixels: Int
    @State private var bytes: Int

    init(
        options: Binding<ConversionOptions>,
        entitlement: Entitlement,
        onProLockTapped: @escaping (ValueGate.Trigger) -> Void = { _ in }
    ) {
        _options = options
        self.entitlement = entitlement
        self.onProLockTapped = onProLockTapped

        switch options.wrappedValue.resizeMode {
        case .none:
            _pixels = State(initialValue: ResizeOption.defaultPixels)
            _bytes = State(initialValue: ResizeOption.defaultBytes)
        case let .maxDimension(pixels):
            _pixels = State(initialValue: pixels)
            _bytes = State(initialValue: ResizeOption.defaultBytes)
        case let .targetBytes(bytes):
            _pixels = State(initialValue: ResizeOption.defaultPixels)
            _bytes = State(initialValue: bytes)
        }
    }

    private var isPro: Bool { entitlement.isPro }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.sectionGap) {
                header
                formatSection
                if options.format.usesQuality {
                    qualitySection
                }
                resizeSection
                stripSection
            }
            .padding(Theme.Spacing.section)
        }
        .background(Theme.Colors.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Options")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { dismiss() } label: {
                Text("Done")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
    }

    // MARK: Format

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.item) {
            sectionTitle("Format")
            HStack(spacing: Theme.Spacing.small) {
                ForEach(OutputFormat.allCases) { format in
                    OptionChip(title: format.displayName, isSelected: options.format == format) {
                        options.format = format
                    }
                }
            }
        }
    }

    // MARK: Quality

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                sectionTitle("Quality")
                Spacer()
                Text(OptionsSummary.qualityText(options.quality))
                    .font(Theme.Typography.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Slider(value: $options.quality, in: 0.1...1.0, step: 0.05)
                .tint(Theme.Colors.accent)
                .accessibilityLabel(Text(String(localized: "Quality")))
                .accessibilityValue(Text(OptionsSummary.qualityText(options.quality)))
        }
    }

    // MARK: Resize

    private var resizeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.item) {
            sectionTitle("Resize")
            HStack(spacing: Theme.Spacing.small) {
                ForEach(ResizeOption.allCases) { option in
                    OptionChip(
                        title: option.displayName,
                        isSelected: ResizeOption(options.resizeMode) == option,
                        locked: option.requiresPro && !isPro
                    ) {
                        selectResize(option)
                    }
                }
            }

            switch ResizeOption(options.resizeMode) {
            case .original:
                EmptyView()
            case .maxDimension:
                presetRow(
                    ResizeOption.pixelPresets,
                    label: pixelLabel,
                    isSelected: { $0 == pixels }
                ) { preset in
                    pixels = preset
                    options.resizeMode = .maxDimension(pixels: preset)
                }
            case .targetSize:
                // Only reachable for Pro users — a free tap on "File size" routes to the paywall
                // and never selects, so the byte presets never show locked.
                if isPro {
                    presetRow(
                        ResizeOption.bytePresets,
                        label: OptionsSummary.byteText,
                        isSelected: { $0 == bytes }
                    ) { preset in
                        bytes = preset
                        options.resizeMode = .targetBytes(preset)
                    }
                }
            }
        }
    }

    private func selectResize(_ option: ResizeOption) {
        if option.requiresPro && !isPro {
            onProLockTapped(.targetSize)
            return
        }
        options.resizeMode = option.mode(pixels: pixels, bytes: bytes)
    }

    private func pixelLabel(_ pixels: Int) -> String { OptionsSummary.pixelText(pixels) }

    /// A row of value-preset chips beneath the active resize mode.
    private func presetRow(
        _ presets: [Int],
        label: @escaping (Int) -> String,
        isSelected: @escaping (Int) -> Bool,
        select: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: Theme.Spacing.small) {
            ForEach(presets, id: \.self) { preset in
                OptionChip(title: label(preset), isSelected: isSelected(preset)) {
                    select(preset)
                }
            }
        }
    }

    // MARK: Strip metadata

    private var stripSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            if isPro {
                Toggle(isOn: $options.stripsMetadata) {
                    stripLabel
                }
                .tint(Theme.Colors.accent)
            } else {
                // Locked: tapping routes to the paywall (task 6.3) rather than enabling the toggle.
                Button {
                    onProLockTapped(.stripMetadata)
                } label: {
                    HStack {
                        stripLabel
                        Spacer()
                        ProLockBadge()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(String(localized: "Pro feature")))
            }
        }
        .padding(Theme.Spacing.item)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.input)
                .fill(Theme.Colors.surface)
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
                .multilineTextAlignment(.leading)
        }
    }

    // MARK: Shared

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.textPrimary)
    }
}

// MARK: - Option chip

/// A pill-shaped, selectable option used for formats, resize modes, and value presets. Optionally
/// shows an amber lock when the choice is Pro-gated for the current user.
private struct OptionChip: View {
    let title: String
    let isSelected: Bool
    var locked = false
    let action: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: Theme.Spacing.tight) {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .font(Theme.Typography.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.item)
            .padding(.horizontal, Theme.Spacing.small)
            .background(isSelected ? Theme.Colors.accent : Theme.Colors.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(locked ? Text(String(localized: "Pro feature")) : Text(""))
    }

    /// Selecting a chip gives selection feedback (design spec §4). A *locked* chip routes to the
    /// paywall instead of selecting, so it stays silent here — the rigid free-cap haptic fires on the
    /// gate hit (`ConvertViewModel.hitGate`) rather than a selection tick.
    private func select() {
        if !locked { Haptics.selection() }
        action()
    }

    private var foreground: Color {
        if isSelected { return Theme.Colors.onAccent }
        return locked ? Theme.Colors.textSecondary : Theme.Colors.textPrimary
    }
}

// MARK: - Previews

#Preview("Free — Light") {
    @Previewable @State var options = ConversionOptions()
    ConversionOptionsSheet(options: $options, entitlement: .free)
        .preferredColorScheme(.light)
}

#Preview("Free — Dark") {
    @Previewable @State var options = ConversionOptions()
    ConversionOptionsSheet(options: $options, entitlement: .free)
        .preferredColorScheme(.dark)
}

#Preview("Pro — resize + strip unlocked") {
    @Previewable @State var options = ConversionOptions(
        format: .heic, resizeMode: .targetBytes(1_000_000), stripsMetadata: true
    )
    ConversionOptionsSheet(options: $options, entitlement: .pro)
}
