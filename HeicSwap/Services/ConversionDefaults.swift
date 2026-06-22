//
//  ConversionDefaults.swift
//  HeicSwap
//
//  The user's persisted conversion defaults — the starting point for every new conversion. Edited
//  in Settings (task 8.1), persisted in `UserDefaults`, and used to seed `ConvertViewModel.options`
//  so a fresh batch opens with the user's preferred format, quality, and metadata-strip choice.
//

import Foundation

/// The user's persisted conversion defaults.
///
/// `@Observable @MainActor` like the other app-wide stores (`EntitlementStore`): Settings binds to
/// it, and the Convert screen mirrors changes into its live session `ConversionOptions` so a changed
/// default is reflected the next time the Options sheet opens (AC1). Only format, quality, and strip
/// persist — **resize is never a default** (it's per-batch intent), so `seedOptions` always starts
/// at `.none` and the Options sheet sets resize each run.
@Observable
@MainActor
final class ConversionDefaults {

    /// Default target format for a new conversion.
    var format: OutputFormat {
        didSet { cache.format = format }
    }

    /// Default compression quality in `0.1...1.0`, applied only to lossy formats (JPEG/HEIC).
    var quality: Double {
        didSet { cache.quality = quality }
    }

    /// Whether new conversions strip EXIF/GPS metadata by default. A Pro feature — Settings gates the
    /// control for free users, but the persisted value is honored once Pro is active.
    var stripsMetadata: Bool {
        didSet { cache.stripsMetadata = stripsMetadata }
    }

    private let cache: ConversionDefaultsCache

    init(cache: ConversionDefaultsCache = ConversionDefaultsCache()) {
        self.cache = cache
        // Seed from the cache so the choices survive launches; a fresh install matches the
        // `ConversionOptions()` defaults (JPEG, 90%, keep metadata).
        self.format = cache.format
        self.quality = cache.quality
        self.stripsMetadata = cache.stripsMetadata
    }

    /// The persisted defaults projected as a starting `ConversionOptions`. Resize is never a default,
    /// so it starts at `.none`; the Options sheet sets resize per batch.
    var seedOptions: ConversionOptions {
        ConversionOptions(
            format: format,
            quality: quality,
            resizeMode: .none,
            stripsMetadata: stripsMetadata
        )
    }
}

/// Persists conversion defaults in `UserDefaults`. Plain preferences — no secrets — so `UserDefaults`
/// is the right, synchronous home, ready before the first frame. Getters fall back to the
/// `ConversionOptions()` defaults when nothing has been stored yet.
struct ConversionDefaultsCache {

    private let defaults: UserDefaults

    private enum Key {
        static let format = "com.heicswap.defaults.format"
        static let quality = "com.heicswap.defaults.quality"
        static let stripsMetadata = "com.heicswap.defaults.stripsMetadata"
    }

    /// Inject a scoped suite in tests; defaults to `.standard` in the app.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var format: OutputFormat {
        get { defaults.string(forKey: Key.format).flatMap(OutputFormat.init(rawValue:)) ?? .jpg }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.format) }
    }

    var quality: Double {
        // `double(forKey:)` returns 0 for a missing key, which is an invalid quality — fall back to
        // the default only when nothing was ever stored.
        get { defaults.object(forKey: Key.quality) == nil ? 0.9 : defaults.double(forKey: Key.quality) }
        nonmutating set { defaults.set(newValue, forKey: Key.quality) }
    }

    var stripsMetadata: Bool {
        get { defaults.bool(forKey: Key.stripsMetadata) }
        nonmutating set { defaults.set(newValue, forKey: Key.stripsMetadata) }
    }
}
