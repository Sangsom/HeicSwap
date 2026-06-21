# App Profile: HeicSwap

> **Last updated**: 2026-06-20
> **Bundle ID**: com.domanovs.rinalds.ios.HeicSwap
> **Minimum iOS**: 26.0
> **Status**: In development (scaffold + tasks 1.1–1.3 · 2.1–2.2 · 3.1–3.5 · 4.1 · 5.1–5.4 complete; Results sheet — sizes, Save to Photos/Files, Share — built; paywall 6.x next)

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
| App shell | `NavigationStack` Convert screen (serif title, on-device trust badge) + Settings entry; Warm Darkroom theme, Dark/Light (task 4.1) | Simple |
| Convert queue | Thumbnail grid fed by the import service — add via Photos/Files, remove (✕ / long-press), clear all, tappable "+N" overflow, safelight glow, empty state (task 5.1) | Moderate |
| Options sheet | `.medium`-detent sheet bound to `ConversionOptions` — format chips (JPG/PNG/HEIC/PDF), quality slider, resize (Original / Max size / File size), strip toggle; amber Pro locks on gated controls (File size, strip); presented from an "Output" summary row below the grid (task 5.2) | Moderate |
| Batch convert + "developing" reveal | The signature moment: a full-width amber Convert CTA runs the on-device engine (images → `ConversionEngine`, PDF → `PDFBuilder`) over the queue; each thumbnail "develops" from a dark, desaturated tile to full color as its item finishes (brightness/saturation sweep), a determinate progress bar + Cancel show overall progress, and a `.success` haptic + completion banner close the run. Reduce Motion swaps the sweep for a pure opacity crossfade. Cancel stops not-yet-started items and keeps the converted ones (task 5.3) | Complex |
| Results sheet (sizes, Save, Share) | Closes the convert loop: a `.large` sheet auto-presents on completion (and re-opens by tapping the completion banner) listing each output with a thumbnail, name, before→after size, and saved-% badge, plus a totals card (file count, total size, total saved). One tap: Share (native `ShareLink` over all outputs), Save to Photos (add-only `PHPhotoLibrary` authorization — images only; PDFs excluded), Save to Files (`UIDocumentPickerViewController` export of the whole batch), and "Convert more" to clear the queue for the next run (task 5.4) | Moderate |

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
├── Models/         # Core Sendable value types (2.1): OutputFormat, ResizeMode, ConversionOptions, SourceItem/ItemStatus, Entitlement — all `nonisolated`; plus ValueGate (2.2) — value-gate policy; ConversionResult (5.4) — one output + its before/after byte sizes, for the Results sheet
├── Services/       # PurchaseService, AnalyticsService, ConversionEngine (3.1 — ImageIO transcode + bounded batch; 3.2 — maxDimension downscale + targetBytes quality search; 3.3 — opt-in EXIF/GPS/maker-note/TIFF strip on the write path), PDFBuilder (3.4 — image→multi-page PDF, one page per image, via UIGraphicsPDFRenderer streaming write + ImageIO downscale-on-load), ImportService (3.5 — PhotosPicker + Files import, iCloud-optimized download with visible progress, ImageIO-validated unsupported-skip; `@MainActor @Observable` + nonisolated `PhotoOriginalLoader`/`FileImportLoader`; `removeAll()` for queue clear-all added in 5.1), ThumbnailCache (5.1 — off-main ImageIO downscale-on-load + NSCache, keyed by file URL, shared by the queue grid and the Results sheet), PhotoLibrarySaver (5.4 — add-only `PHPhotoLibrary` save of image outputs; requests `.addOnly` authorization, never reads the library)
├── Features/       # Convert (4.1 shell + 5.1 queue + 5.2 options + 5.3 batch convert — `ConvertView`/`ConvertViewModel` (owns shared `options` + stubbed `entitlement`, and the convert lifecycle: `ConversionPhase`, `convert()`/`cancelConversion()`, per-item `developedItemIDs`, retained `lastOutputs`; drives `ConversionEngine`/`PDFBuilder`, bridging their off-actor per-item callbacks onto the main actor via an `AsyncStream`, with a `.success` haptic on completion), `QueueGridView` 4-col grid with "+N" overflow + safelight glow + the develop reveal, pure `QueueLayout` math, `ConvertRoute`; `ConversionOptionsSheet` + the "Output" `OptionsSummaryRow`, pure `OptionsSummary` (summary text) + `ResizeOption` (ResizeMode↔picker projection + Pro gate); the convert CTA / progress / completion `ConvertActionSection` + pure `DevelopReveal` (the dark→color sweep, with the Reduce-Motion opacity-crossfade fallback); 5.4 Results sheet — `ResultsSheet` (auto-presents on finish; per-output rows, totals card, ShareLink + Save to Photos/Files + Convert-more) over the VM's `lastResults: [ConversionResult]`, plus pure `ResultsSummary` (totals / saved-% / size formatting)), Settings (placeholder, pushed destination), Import (3.5 — PhotosImportButton, FilesImportButton; the standalone ImportView harness was removed once 5.1's real queue replaced it)
├── DesignSystem/   # Warm Darkroom tokens — Theme namespace: Colors, Typography (+Font.serif), Layout, Gradients (task 1.3)
├── Resources/      # Assets, LaunchScreen
├── Components/     # EmptyStateView, OnDeviceBadge (reusable ⛊ on-device trust badge — 4.1), ProLockBadge (reusable amber 🔒 PRO affordance — 5.2), PaywallPresenter
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
| Flaky test: `ConversionEngineTests` batch-progress | Low | Pre-existing (task 3.1). The test's `@Sendable` progress callback spawns an unawaited `Task { await actor.record(...) }`, then asserts before those detached tasks land → intermittently reports N−1 of N callbacks. Test-only race, not a product bug (the engine fires once per item; `outcomes.count` is deterministic). Fix: `await` the recording or use a synchronous collector |
| `ConvertView` not previewable in Xcode canvas | Low | Xcode 26.5's `__designTimeSelection` preview instrumentation breaks overload resolution for `toolbar`/`ScrollView`/`background(_:in:)`. The app builds and runs fine; the constituent views (`QueueGridView`, `ConvertEmptyState`) preview individually |
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
| 2026-06-21 | Built the Convert queue (task 5.1): `QueueGridView` — a 4-column `LazyVGrid` fed by `ImportService` with per-thumbnail ✕ / long-press remove, a tappable "+N" overflow tile (pure `QueueLayout` math), a subtle safelight glow, and ≥44pt targets — plus an inviting empty state (serif "Drop in a photo to begin" + amber Add Photos / Files). Added `ConvertViewModel` (owns `ImportService`; the screen's state owner for 5.2/5.3) and `ThumbnailCache` (off-main ImageIO downscale + NSCache). Added `ImportService.removeAll()` for clear-all; removed the now-superseded `ImportView` harness. Added `QueueLayoutTests` (5 cases incl. the design-spec 3+"+9" mock); 51 tests total. Build green; empty state + grid verified via Light/Dark preview renders | 5.1 via /task |
| 2026-06-21 | Built the app shell (task 4.1): `ConvertView` root in a `NavigationStack` — serif "Convert" title, the persistent `OnDeviceBadge`, an empty-state placeholder, and a Settings entry that pushes via a type-safe `ConvertRoute` enum. Warm Darkroom theme + Dark/Light adapt app-wide (asset tokens; no forced scheme — verified via Light/Dark preview renders). Entry point now renders `ConvertView` with `AppState` + services in the environment. Removed the template `MainTabView` + `HomeScreen` and `AppState.selectedTab`/`MainTab`; `SettingsScreen` is now a pushed destination (no nested stack). Added reusable `OnDeviceBadge` (Components/). Build green; all 46 tests still pass | 4.1 via /task |
| 2026-06-21 | Built the Options sheet (task 5.2): `ConversionOptionsSheet` — a `.medium`/`.large`-detent sheet bound to the screen's shared `ConversionOptions` (format chips, quality slider shown only for lossy formats, resize Original/Max-size/File-size with px & byte presets, strip toggle). Advanced choices (File-size resize, strip) carry amber Pro locks for free users via the new reusable `ProLockBadge`; a free tap routes to `onProLockTapped` (paywall seam, task 6.2) instead of acting — Pro users see no locks and the controls function. Options live on `ConvertViewModel` (persist as session defaults) alongside a stubbed `entitlement` (`.free` until the entitlement client, task 6.1). Entry point is a tappable "Output" summary row below the grid. Extracted pure, tested presentation helpers — `OptionsSummary` (one-line summary text) and `ResizeOption` (ResizeMode↔picker projection + Pro gate). Added `OptionsSheetTests` (2 suites — summary fragments/quality rounding/byte+px labels, resize projection/gate/round-trip); 62 tests total, passing. Verified Light/Dark + free/Pro lock states via preview renders | 5.2 via /task |
| 2026-06-21 | Wired the batch Convert action + the signature "developing" reveal (task 5.3). `ConvertViewModel` gained the convert lifecycle (`ConversionPhase` idle/converting/finished, `convert()`/`cancelConversion()`, per-item `developedItemIDs`, retained `lastOutputs`, `conversionTotal`): it pairs each file-backed queue item with its id, routes image formats to `ConversionEngine.convertBatch` and `.pdf` to `PDFBuilder.buildPDF`, and bridges their off-actor per-item callbacks (`onItemCompleted`/`onPageRendered`) onto the main actor through an `AsyncStream` consumed in order — the producer runs as a structured `async let` child so cancelling the task propagates straight into the engine's task group (in-flight items finish and are kept, not-yet-started ones stop; AC3). A `.success` `UINotificationFeedbackGenerator` fires on natural completion. `QueueCell` now applies the pure `DevelopReveal` recipe (a dark+desaturated→full-color brightness/saturation sweep, replaced by an opacity-only crossfade under `accessibilityReduceMotion`; AC2), animating each thumbnail as its id lands in `developedItemIDs`; the grid expands on convert so the whole batch reveals. Added the `ConvertActionSection` (full-width amber Convert CTA → determinate progress + Cancel → completion banner); add/clear/options controls disable while converting. Added `DevelopRevealTests` (3 — developed=full-color, AC2 crossfade-only vs. sweep) + `ConvertViewModelTests` (4 — AC1 whole-queue convert/develop/outputs-kept, `.pdf`→one output, empty-queue + already-running guards, options-edit clears banner); 69 tests total, passing. Cancel is timing-dependent → manual | 5.3 via /task |
| 2026-06-21 | Built the Results sheet (task 5.4) — closes the convert loop. `ConvertViewModel` now retains `lastResults: [ConversionResult]` (each output paired with its source byte size, summed across inputs for the combined PDF; `lastOutputs` kept as a derived `[URL]`). New `ConversionResult` model (before/after sizes, `bytesSaved`, `isPDF`) + pure `ResultsSummary` (totals / saved-% / `ByteCountFormatter` size text). `ResultsSheet` auto-presents the moment a run finishes (re-openable by tapping the completion banner): per-output rows (thumbnail via the shared `ThumbnailCache`, PDF→doc glyph, before→after size, saved-% badge), a totals card, and one-tap **Share** (`ShareLink` over all outputs, AC3), **Save to Photos** (new `PhotoLibrarySaver` — add-only `PHPhotoLibrary` authorization, images only, AC2), **Save to Files** (`UIDocumentPickerViewController` export of the whole batch), and **Convert more** (clears the queue). Added `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription` (add-only string) to both app configs. Added `ResultsSummaryTests` (14 — `ConversionResult` math + `ResultsSummary` totals/savings/AC1) + 2 `ConvertViewModelTests` (AC1 before/after sizes; PDF original = sum of inputs); 83 tests, all passing apart from the pre-existing `ConversionEngineTests` batch-progress flake (§7). Temp-file purging after save/dismiss is deferred to task 10.3 per the task's developer note | 5.4 via /task |
| 2026-06-21 | Built `PDFBuilder` actor (Services/) — image→multi-page PDF, the top ASO acquisition surface ("convert image to pdf"). `buildPDF(from:maxPageDimension:fileName:onPageRendered:)` writes one page per image in queue order via `UIGraphicsPDFRenderer.writePDF(to:)`, streaming each page straight to a per-run temp file (the whole PDF is never held in memory); each source is loaded downscaled via `CGImageSourceCreateThumbnailAtIndex` (cap default 2048px, orientation baked in, no upscale) so only one bounded bitmap exists at a time inside a per-page `autoreleasepool` — chosen over PDFKit's in-memory `PDFDocument` precisely for that memory bound (AC3). Pages sized to each image's aspect; unreadable sources are skipped, and an empty/all-unreadable build throws `PDFBuilderError.noReadableImages`; honors cancellation. PDF assembly is the N→1 counterpart to the engine's N→N transcode, so it's its own service (the engine still rejects `.pdf`). Added `PDFBuilderTests` (9 tests — AC1 5-page order via per-page aspect, AC2 single page, AC3 downscale-to-cap, no-upscale, per-page progress, empty/all-corrupt throw, mixed-corrupt skip; 41 tests total, passing) | 3.4 via /task |
