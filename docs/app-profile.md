# App Profile: HeicSwap

> **Last updated**: 2026-06-20
> **Bundle ID**: com.domanovs.rinalds.ios.HeicSwap
> **Minimum iOS**: 26.0
> **Status**: In development (scaffold + tasks 1.1–1.3 · 2.1–2.2 · 3.1–3.5 · 4.1 complete; app shell built, Phase 5 feature work next)

---

## 1. What This App Does

### One-Liner
On-device HEIC & image converter

### Description
HeicSwap converts HEIC/PNG/JPG images, builds multi-page PDFs, resizes/compresses, and strips EXIF/GPS metadata — entirely **on-device, with zero network egress**. Nothing is ever uploaded; privacy is the core promise.

### Target Audience
People who need to convert iPhone HEIC photos to shareable formats (JPG/PNG/PDF) and who care that their images never leave the device.

---

## 2. Feature Inventory

### Core Features (Shipped)
| Feature | Description | Complexity |
|---------|-------------|-----------|
| App shell | `NavigationStack` Convert screen (serif title, on-device trust badge, empty-state placeholder) + Settings entry; Warm Darkroom theme, Dark/Light (task 4.1) | Simple |

### Planned (v1.0.0 MVP — see `docs/PRD-HeicSwap-v1.md` / `docs/dev-tasks-HeicSwap.md`)
| Feature | Description |
|---------|-------------|
| Import | PhotosPicker + Files + iCloud-optimized download (never upload) |
| On-device engine | HEIC/PNG/JPG conversion via ImageIO; bounded-concurrency batch |
| Image → PDF | N images → one multi-page PDF (top ASO acquisition surface) |
| Resize / compress | Max dimension + resize-to-target-file-size |
| EXIF/GPS strip | Privacy-critical metadata removal |
| Output / Share | Save to Photos/Files; batch share |
| Value-gated paywall | Free basic + small PDF (≤ ~5); Pro for large batch, resize-to-size, strip |
| Onboarding · Settings | ≤3 screens; defaults, restore/manage, privacy statement |

### Deferred to v1.1
RAW input · WebP output · Share Extension · history/presets · iPad

---

## 3. Technical Stack

| Component | Choice | Notes |
|-----------|--------|-------|
| UI Framework | SwiftUI | SwiftUI-first |
| Architecture | MVVM with `@Observable` | Services injected via `@Environment`; `AppState` root |
| Data Persistence | None planned | Stateless converter; value types (Sendable) |
| Networking | None | **Zero network egress** is a product guarantee (CI test in task 10.4) |
| Monetization | RevenueCat | Behind `PurchaseClient` protocol (`PurchaseService` wrapper); paywall in 6.x |
| Analytics | TelemetryDeck (wired) + MetricKit (planned) | Privacy-first; **no Firebase**. SDK behind `AnalyticsClient` (`TelemetryDeckAnalyticsClient`); events in 9.1 |
| CI/CD | Fastlane | `build` / `beta` / `screenshots` lanes |
| Swift Version | 6.0 | Strict concurrency = complete; default actor isolation = MainActor |

### Dependencies
| Package | Purpose | Risk |
|---------|---------|------|
| RevenueCat (purchases-ios 5.79.0) | Subscriptions / paywall | Low |
| TelemetryDeck (SwiftSDK 2.14.1) | Privacy-first analytics | Low |

> The only two third-party SDKs, both pinned to the current major (`upToNextMajorVersion`). Each is fronted by a thin protocol (`PurchaseClient` / `AnalyticsClient`) so feature code never imports them directly — only `PurchaseService`, `TelemetryDeckAnalyticsClient`, and the (later) paywall component do. API keys come from `.secrets` → `Secrets.xcconfig` → Info.plist → `SecretsProvider` (never hardcoded). SDK init is deferred to `AppState.loadInitialState()` (`.task`, after first frame).
>
> Firebase (Analytics + Crashlytics) was removed from the template during task 1.1 — it conflicts with HeicSwap's zero-network / privacy-first positioning. TelemetryDeck is wired in 1.2; the event catalog + MetricKit land in task 9.1.

---

## 4. App Structure

### Navigation Pattern
A `NavigationStack` whose root is `ConvertView` (task 4.1): serif "Convert" title, the persistent `OnDeviceBadge`, an empty-state placeholder, and a Settings entry in the nav bar that pushes via a type-safe `ConvertRoute` enum. Warm Darkroom theme + Dark/Light adapt app-wide (asset-catalog tokens; no forced color scheme). The template tab bar was removed. Phase 5 slots the queue/options/convert flow into the root and extends `ConvertRoute`.

### Source Layout
```
HeicSwap/
├── App/            # HeicSwapApp (root = ConvertView), AppDelegate (minimal), AppState
├── Models/         # Core Sendable value types (2.1): OutputFormat, ResizeMode, ConversionOptions, SourceItem/ItemStatus, Entitlement — all `nonisolated`; plus ValueGate (2.2) — value-gate policy
├── Services/       # PurchaseService, AnalyticsService, ConversionEngine (3.1 — ImageIO transcode + bounded batch; 3.2 — maxDimension downscale + targetBytes quality search; 3.3 — opt-in EXIF/GPS/maker-note/TIFF strip on the write path), PDFBuilder (3.4 — image→multi-page PDF, one page per image, via UIGraphicsPDFRenderer streaming write + ImageIO downscale-on-load), ImportService (3.5 — PhotosPicker + Files import, iCloud-optimized download with visible progress, ImageIO-validated unsupported-skip; `@MainActor @Observable` + nonisolated `PhotoOriginalLoader`/`FileImportLoader`)
├── Features/       # Convert (4.1 — ConvertView root shell: NavigationStack + serif title + OnDeviceBadge + empty-state placeholder + Settings push; ConvertRoute), Settings (placeholder, now a pushed destination), Import (3.5 — PhotosImportButton, FilesImportButton; ImportView harness retired from the shell, reused by 5.1)
├── DesignSystem/   # Warm Darkroom tokens — Theme namespace: Colors, Typography (+Font.serif), Layout, Gradients (task 1.3)
├── Resources/      # Assets, LaunchScreen
├── Components/     # EmptyStateView, OnDeviceBadge (reusable ⛊ on-device trust badge — 4.1), PaywallPresenter
├── Core/           # ServiceEnvironment (DI), utilities, placeholders
└── Documentation/  # Features.md
```

---

## 5. Monetization

### Current Model
Subscription + lifetime (hard paywall model, value-gated). Not yet implemented (task 6.x).

### Products (planned — task 6.1)
| Product | Type | Price |
|---------|------|-------|
| Pro Annual | Annual | $9.99 |
| Pro Weekly | Weekly | $1.99 |
| Pro Lifetime | One-time | $19.99 |

### Paywall Strategy
Honest paywall (annual default, restore, no dark patterns) presented on Pro-gated actions. Free tier: basic conversion + small PDF up to ~5 items.

---

## 6. App Store Presence

Not yet submitted. Metadata (name/subtitle/keywords via Astro), 5 screenshots, and an accurate privacy label are produced in task 11.1.

---

## 7. Known Issues & Technical Debt

| Issue | Severity | Notes |
|-------|----------|-------|
| Orphaned import harness | Low | `ImportView` (+ `PhotosImportButton`/`FilesImportButton`) is no longer wired into navigation after the 4.1 shell replaced the tab placeholder; kept because task 5.1 reuses it for the real queue UI. Exercisable via Xcode preview until then |
| Leftover `firebase-debug.log` | Low | Stray file in repo root from prior Firebase tooling; unrelated to the build, safe to delete |

---

## 8. Source Discrepancies

| Document Says | Code Shows | Resolution |
|--------------|-----------|------------|
| README/Features.md referenced `StoreKit.storekit` & Firebase setup | No such file; Firebase removed | Docs corrected during task 1.1 |

---

## 9. Changelog

| Date | Changes | Triggered By |
|------|---------|-------------|
| 2026-06-20 | Initial profile created; project scaffolded (Swift 6 / iOS 26 / strict concurrency), renamed RDTemplate → HeicSwap, Firebase removed | 1.1 via /task |
| 2026-06-20 | Added TelemetryDeck (SwiftSDK 2.14.1) via SwiftPM; both SDKs fronted by `PurchaseClient`/`AnalyticsClient` protocols; config-based keys; deferred init | 1.2 via /task |
| 2026-06-20 | Built Warm Darkroom design system: 11 light/dark color tokens (asset catalog), serif display type scale + `Font.serif(_:weight:)` helper, 4pt spacing + radius constants, safelight gradient; `AccentColor` set to safelight amber; debug-only token-gallery preview | 1.3 via /task |
| 2026-06-20 | Defined core domain value types in `Models/` (OutputFormat, ResizeMode, ConversionOptions, SourceItem/ItemStatus/Source, Entitlement) — all `nonisolated` + `Sendable` to cross the engine/UI actor boundary under default-MainActor isolation; removed Models placeholder; hosted `HeicSwapTests` in the app (`TEST_HOST`/`BUNDLE_LOADER`) so it can `@testable import` the SwiftUI module; added `CoreModelsTests` (6 tests, passing) | 2.1 via /task |
| 2026-06-20 | Added `ValueGate` (Models/) — single-source-of-truth value-gate policy: centralized `freeBatchLimit` (=5; A/B knob 3/5/8) + pure, stateless `requiresPro(items:options:)` (batch > limit ∥ stripsMetadata ∥ resize `.targetBytes`; PDF and `.maxDimension` stay free; no daily counter); added `ValueGateTests` (8 tests / 14 cases — AC1–3, batch boundary 4/5/6, empty batch, per-format, combined triggers; passing) | 2.2 via /task |
| 2026-06-20 | Built `ConversionEngine` actor (Services/) — on-device ImageIO transcode HEIC/PNG/JPG → JPG/PNG/HEIC via `CGImageSourceCreateWithURL` + `CGImageDestinationAddImageFromSource` (color profile + metadata preserved, no held bitmap); `convertBatch` runs a bounded `TaskGroup` (2–4 in-flight, clamped to core count) with `autoreleasepool` per item, per-item `@Sendable` completion callback, and failure isolation; outputs to a per-run temp dir with collision-free names. `ConversionError`/`ConversionOutcome` are `nonisolated`+`Sendable`. PDF rejected (deferred to 3.4); resize/strip left as passthrough for 3.2/3.3. Added `ConversionEngineTests` (8 tests — AC1 valid+color-preserved across JPG/PNG/HEIC, AC2 per-item progress, AC3 corrupt-file isolation, empty batch, name collisions; passing) | 3.1 via /task |
| 2026-06-20 | Added resize/compress to `ConversionEngine` — `encode` now dispatches on `ResizeMode`: `.none` keeps the faithful passthrough, `.maxDimension` downscales via `CGImageSourceCreateThumbnailAtIndex` (`kCGImageSourceThumbnailMaxPixelSize`, downsample-on-load, transform-applied, no upscale), `.targetBytes` runs a bounded JPEG/HEIC quality binary search (full-quality fast-path probe + ≤8 halvings, encodes from source frame into memory so no bitmap is held) landing at/under target; lossless (PNG) targetBytes falls back to a faithful encode. Output size read from disk (URL-based API unchanged). Added 6 `ConversionEngineTests` cases (AC1 maxDimension 2048 + aspect, no-upscale, large-photo downscale; AC2 targetBytes ≤ target + full-quality-fits + lossless fallback; 29 tests total, passing) | 3.2 via /task |
| 2026-06-20 | Added opt-in metadata stripping to `ConversionEngine` (privacy core) — when `ConversionOptions.stripsMetadata` is set, a shared `sourceCopyProperties` helper marks the identifying ImageIO dictionaries (`Exif`, `ExifAux`, `GPS`, `TIFF`, `IPTC`, Apple/Canon/Nikon/Minolta/Fuji/Olympus/Pentax maker notes) `kCFNull` on the two `…AddImageFromSource` paths (passthrough + `targetBytes`), dropping them from the copy; the `.maxDimension` thumbnail path is metadata-clean by construction. Verified against ImageIO behavior: GPS removed entirely, identifying TIFF (make/model/software/timestamp) removed while the structural `Orientation` tag + ICC color profile are retained, so images stay upright (JPEG keeps only structural `Exif` pixel-dimension/color-space tags). Strip OFF (default) preserves all metadata via the faithful passthrough. Added 4 `ConversionEngineTests` cases against a real-photo-shaped geotagged fixture (AC1 strip ON over passthrough/targetBytes/maxDimension; AC2 strip OFF preserves GPS+Exif+TIFF; 33 tests total, passing) | 3.3 via /task |
| 2026-06-21 | Built `ImportService` (Services/) — gets images into the queue from `PhotosPicker` + Files, materializing each into a local original the engine reads by URL (100% on-device, never uploaded). Photos use `PhotosPickerItem.loadTransferable(type:completionHandler:)`, whose returned `Progress` drives a visible "Downloading from iCloud…" state with real fractional progress **and needs no photo-library permission** (selection is scoped to the picked items) — deliberately *not* `PHImageManager`/`PHAsset`, which would require library authorization and break the "no full-library permission" promise. Files via `.fileImporter` (filtered to supported image UTTypes) with security-scoped copy. Every materialized source is ImageIO-validated; unsupported/undecodable inputs are flagged into `skipped`, never crashed (AC3). `@MainActor @Observable` orchestrator (observable `items`/`active`/`skipped`) over nonisolated `PhotoOriginalLoader`/`FileImportLoader` that run file work off the main actor. Added reusable `PhotosImportButton`/`FilesImportButton` + an `ImportView` harness wired into Home for manual verification (Convert shell 4.1 / queue UI 5.1 replace it). Added `ImportServiceTests` + `FileImportLoaderTests` (5 tests — AC1 Files order preserved, AC3 unsupported rejected/skipped over the loader and service, remove-by-id; Photos/iCloud paths are manual; 46 tests total, passing) | 3.5 via /task |
| 2026-06-21 | Built the app shell (task 4.1): `ConvertView` root in a `NavigationStack` — serif "Convert" title, the persistent `OnDeviceBadge`, an empty-state placeholder, and a Settings entry that pushes via a type-safe `ConvertRoute` enum. Warm Darkroom theme + Dark/Light adapt app-wide (asset tokens; no forced scheme — verified via Light/Dark preview renders). Entry point now renders `ConvertView` with `AppState` + services in the environment. Removed the template `MainTabView` + `HomeScreen` and `AppState.selectedTab`/`MainTab`; `SettingsScreen` is now a pushed destination (no nested stack). Added reusable `OnDeviceBadge` (Components/). Build green; all 46 tests still pass | 4.1 via /task |
| 2026-06-21 | Built `PDFBuilder` actor (Services/) — image→multi-page PDF, the top ASO acquisition surface ("convert image to pdf"). `buildPDF(from:maxPageDimension:fileName:onPageRendered:)` writes one page per image in queue order via `UIGraphicsPDFRenderer.writePDF(to:)`, streaming each page straight to a per-run temp file (the whole PDF is never held in memory); each source is loaded downscaled via `CGImageSourceCreateThumbnailAtIndex` (cap default 2048px, orientation baked in, no upscale) so only one bounded bitmap exists at a time inside a per-page `autoreleasepool` — chosen over PDFKit's in-memory `PDFDocument` precisely for that memory bound (AC3). Pages sized to each image's aspect; unreadable sources are skipped, and an empty/all-unreadable build throws `PDFBuilderError.noReadableImages`; honors cancellation. PDF assembly is the N→1 counterpart to the engine's N→N transcode, so it's its own service (the engine still rejects `.pdf`). Added `PDFBuilderTests` (9 tests — AC1 5-page order via per-page aspect, AC2 single page, AC3 downscale-to-cap, no-upscale, per-page progress, empty/all-corrupt throw, mixed-corrupt skip; 41 tests total, passing) | 3.4 via /task |
