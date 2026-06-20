# PRD: HeicSwap — Image Converter

> **Version**: v0.9 (Draft)
> **Date**: 2026-06-19
> **Status**: Draft — pending Devil's Advocate review (Stage 4) + Tech Lead addendum (Stage 5)
> **Author**: Product Team (AI-assisted) · PM pass
> **Source**: `docs/discovery-heicswap.html` (Opportunity 8.0/10 · BUILD) · idea-loop seed "HeicSwap" (Score 75 · Validated)

---

## Changelog

| Version | Date | Changes | Triggered By |
|---------|------|---------|-------------|
| v0.9 | 2026-06-19 | Initial draft PRD | Discovery complete + pricing locked |
| v0.95 | 2026-06-19 | Tech Lead addendum (§6); architecture designed around the review-trimmed v1 | Critic review + Tech assessment |

**Locked decisions carried from Discovery:**
- **On-device only** — no server/cloud conversion, ever. This is the core wedge, not a feature.
- **Pricing ladder**: Annual **$9.99/yr** (hero) · Weekly **$1.99/wk** (secondary, transparent) · Lifetime **$19.99** (one-time, churn-proof). Free tier = daily conversion cap.
- **Scope**: 4–6 week "deep" MVP — RAW, multi-page image→PDF, resize-to-target, EXIF strip, one-tap batch, Share-sheet extension.
- **ASO**: App Store *name* leads with "Image Converter"; "HeicSwap" is the brand (don't let it narrow the listing to HEIC-only).

---

## 1. Product Overview

### One-Liner (App Store subtitle, ≤30 char)
**`HEIC to JPG, PDF & Resize`** (25 char)

### Problem Statement
Every iPhone shoots HEIC by default, so users repeatedly hit a wall: a website rejects their photo, an Android friend can't open it, a form caps the file size, or they need photos as a single PDF. The free apps that solve this either **upload your private photos to a server**, **bury a 5-second task in ads**, or **spring a surprise weekly subscription** — and Apple's own Files/Shortcuts path is invisible to mainstream users and can't do RAW, WebP, multi-page PDF, or resize-to-size.

### Vision
In 12 months, HeicSwap is the **default "just make it a normal file" app** — the one people recommend because it's fast, private (nothing leaves the phone), ad-free, and honestly priced. It is also the proven **on-device file/media engine** that powers sibling utilities (SizeFit, UnzipX).

### Target Audience
**Primary persona — "Blocked Sender"**: 20–55, non-technical, doesn't know Shortcuts exists. Just needs a normal JPG / a smaller file / a PDF *right now* to finish an upload or send a photo. Maps to the highest-volume keywords (image converter, heic to jpg, convert image to pdf, image size).
**Secondary persona — "Prosumer / RAW shooter"**: wants RAW→JPG, WebP, and batch control. Supplies the recurring-use revenue a pure single-use audience wouldn't.

### Anti-Goals — what HeicSwap explicitly does NOT do
- **No server/cloud upload or accounts** — all conversion is on-device. (This is the differentiator; violating it kills the product.)
- **No ads.**
- **No photo editing** (filters, crop, retouch) beyond resize/compress — stay a converter.
- **No dark-pattern monetization** — no fake "free trial" that auto-charges, no one-photo-at-a-time tease, no hidden weekly default.
- **No Android/web version** for v1 — iOS-native focus.

---

## 2. Goals & Success Metrics

### Primary KPI
**Free→Paid conversion ≥ 3.5%** of activated users (blended across subscription + lifetime), measured in RevenueCat.

### Secondary KPIs
| Metric | Target | Measurement |
|--------|--------|-------------|
| Activation (≥1 successful conversion in first session) | > 80% | Firebase Analytics |
| Paywall view → purchase | > 6% | RevenueCat |
| App Store rating | > 4.6 | App Store Connect |
| 30-day repeat usage (tests recurring-use thesis) | > 25% | Firebase Analytics |
| Crash-free sessions | > 99.5% | Firebase Crashlytics |
| Refund rate (guards against accidental/regret purchases) | < 2% | App Store Connect |

---

## 3. Feature Specification

### Must Have (MVP — v1.0)

#### 3.1 Photo & File Import
**Priority**: Must Have
**User Story**: As a Blocked Sender, I want to pick photos (or files) quickly, so that I can start converting without hunting.
**Acceptance Criteria**:
- [ ] Given the home screen, when I tap "Add Photos", then the system PHPicker opens with **multi-select** enabled (no full library permission required).
- [ ] Given the picker, when I select up to the system limit, then all selected items appear as thumbnails in a convert queue.
- [ ] Given I want a non-photo source, when I tap "Import from Files", then the document picker opens filtered to supported image types.
- [ ] Given an unsupported file, when it's imported, then it's flagged inline ("Can't convert this type") and skipped, not crashed.
**Effort**: M
**Notes**: Use `PHPickerViewController` (privacy-friendly, no permission prompt). Files import via `UIDocumentPicker`. Preserve original order.

#### 3.2 On-Device Conversion Engine
**Priority**: Must Have
**User Story**: As a user, I want to convert between common image formats entirely on my device, so that my photos stay private and it works offline.
**Acceptance Criteria**:
- [ ] Given imported images, when I choose a target format, then conversion runs **100% on-device** (ImageIO / Core Image) with no network call.
- [ ] Given input HEIC/HEIF, PNG, JPG, WebP, TIFF, or RAW (DNG/CR2/NEF/ARW), when I convert, then I can output **JPG, PNG, HEIC, or WebP**.
- [ ] Given a conversion, when it completes, then color profile is preserved and quality matches the chosen setting (no visible degradation at "High").
- [ ] Given airplane mode, when I convert, then it succeeds (proves on-device).
**Effort**: L
**Notes**: RAW decode via `CIRAWFilter`. WebP encode/decode — confirm native support (iOS 14+ decodes WebP; **encoding may need a check / lightweight dependency** — flag for Tech Lead). This is the privacy claim's technical backbone; **add an automated test asserting zero network egress during conversion.**

#### 3.3 One-Tap Batch Conversion
**Priority**: Must Have
**User Story**: As a Blocked Sender, I want to convert a whole batch in one tap, so that I don't repeat the task per photo.
**Acceptance Criteria**:
- [ ] Given multiple images in the queue, when I tap Convert, then **all** are converted in one action with a visible progress indicator and per-item status.
- [ ] Given a large batch (test 100+ items), when converting, then the UI stays responsive and memory stays bounded (stream, don't load all at once).
- [ ] Given a mid-batch failure on one item, when it fails, then the rest continue and the failed item is reported, not the whole batch aborted.
- [ ] Given the free tier, when a batch would exceed the daily cap, then conversion proceeds up to the cap and the paywall is offered for the remainder (see 3.8).
**Effort**: M
**Notes**: "Select all" / batch is **free up to the daily cap** — this is the anti-"one-photo-free" differentiator. Use a `TaskGroup` with bounded concurrency.

#### 3.4 Image → Multi-Page PDF
**Priority**: Must Have
**User Story**: As a form-filler, I want to combine several photos into one PDF, so that I can attach it to an application.
**Acceptance Criteria**:
- [ ] Given 2+ selected images, when I choose "To PDF", then a single multi-page PDF is produced, one image per page, in queue order.
- [ ] Given the PDF output, when I preview it, then page order matches and orientation is correct.
- [ ] Given a single image, when I choose "To PDF", then a valid one-page PDF is produced.
**Effort**: M
**Notes**: `PDFKit` / `UIGraphicsPDFRenderer`. Owns the low-difficulty "convert image to pdf" keyword — the native path can't do this in one tap.

#### 3.5 Resize / Compress to Target
**Priority**: Must Have
**User Story**: As a Blocked Sender, I want to shrink a photo to under a size limit, so that an upload form accepts it.
**Acceptance Criteria**:
- [ ] Given an image, when I set a target (max dimension in px **or** target file size like "under 2 MB"), then output respects it.
- [ ] Given a target file size, when I convert, then the app iterates quality to land at or just under the target and reports the resulting size.
- [ ] Given presets ("Web < 2MB", "Email", "Original"), when I tap one, then the corresponding settings apply.
**Effort**: M
**Notes**: Target-file-size resize is a genuine native-path gap and a recurring-use hook. Binary-search the JPEG quality parameter.

#### 3.6 Strip EXIF / Location Metadata
**Priority**: Must Have
**User Story**: As a privacy-conscious user, I want to remove GPS/EXIF before sharing, so that I don't leak where a photo was taken.
**Acceptance Criteria**:
- [ ] Given a conversion, when "Remove location & metadata" is ON, then output contains no GPS/EXIF/maker-note data (verify with a metadata inspector).
- [ ] Given the toggle is OFF, when I convert, then metadata is preserved.
- [ ] Given the setting, when I change it, then it persists as my default.
**Effort**: S
**Notes**: Reinforces the privacy brand. Default OFF (preserve) to avoid surprising users; surface prominently.

#### 3.7 Output & Sharing
**Priority**: Must Have
**User Story**: As a user, I want to save or send my converted files where I need them, so that the task is actually finished.
**Acceptance Criteria**:
- [ ] Given completed conversions, when I tap Save, then I can choose **Save to Photos**, **Save to Files**, or **Share** (system share sheet).
- [ ] Given Save to Photos, when invoked, then it requests add-only Photos permission (not full library).
- [ ] Given a batch, when I share, then all outputs are included.
**Effort**: S
**Notes**: Add-only Photos permission (`PHPhotoLibrary` add). Keep the post-conversion screen one tap from done.

#### 3.8 Freemium Daily Cap + Paywall (RevenueCat)
**Priority**: Must Have
**User Story**: As the business, I want a generous free tier that converts to paid at the moment of need, so that we monetize at install volume without dark patterns.
**Acceptance Criteria**:
- [ ] Given a free user, when they convert, then up to **N conversions/day** (default N=10 — A/B candidate) are free, watermark-free, ad-free.
- [ ] Given the cap is reached (or a Pro-only action: RAW, WebP, batch beyond cap, PDF beyond cap, resize-to-target), when triggered, then the **paywall** appears showing $9.99/yr (default-highlighted), $1.99/wk, and $19.99 lifetime, with **Restore Purchases**.
- [ ] Given a purchase, when completed, then all Pro features unlock immediately and the cap is removed; entitlement is checked via RevenueCat.
- [ ] Given the paywall, when I dismiss it, then I keep any remaining free allowance and am not blocked from the free tier.
- [ ] Given a returning paid user offline, when they launch, then cached entitlement grants access (no online check required to convert).
**Effort**: L
**Notes**: RevenueCat with three products. **No timed free trial at launch** — the daily cap is the trial. Pro gating: define exactly which features are free vs Pro (see Open Questions Q1). Honest paywall copy — no fake countdowns.

#### 3.9 Share Extension
**Priority**: Must Have (part of the "deep" scope)
**User Story**: As a user, I want to convert straight from another app's share sheet, so that I don't have to open HeicSwap first.
**Acceptance Criteria**:
- [ ] Given a photo in Photos/Files/Mail, when I tap Share → HeicSwap, then a compact converter UI appears with format options.
- [ ] Given the extension, when I convert, then output saves/shares without leaving the host context, respecting the same free cap + entitlement.
**Effort**: M
**Notes**: App Extension target; share entitlement + free-cap state via App Group with the main app.

#### 3.10 Onboarding
**Priority**: Must Have
**User Story**: As a first-time user, I want to immediately understand the value and grant the right permission, so that I can convert in under a minute.
**Acceptance Criteria**:
- [ ] Given first launch, when onboarding shows, then it is **≤3 screens** (value prop → privacy/on-device promise → start), each skippable.
- [ ] Given onboarding, when I reach the end, then I land on the home/empty state ready to add photos.
- [ ] Given I skip, when skipped, then I still reach a usable home screen.
**Effort**: S
**Notes**: Lead screen 1 with the privacy promise ("Your photos never leave your iPhone"). No account, no paywall during onboarding.

#### 3.11 Settings
**Priority**: Must Have
**Acceptance Criteria**:
- [ ] Given Settings, when opened, then I can set default output format & quality, default metadata-strip behavior, manage/restore subscription, and view a privacy statement.
- [ ] Given "Restore Purchases", when tapped, then entitlements re-sync via RevenueCat.
**Effort**: S
**Notes**: Include links to Privacy Policy & Terms (required for subscriptions).

---

### Should Have (v1.1)

#### Files App / Action Extension
Convert directly inside the Files app (file provider / Action extension). Deepens the "zero-setup" advantage. **Effort**: M.

#### Output Presets Library
User-savable presets ("Job application PDF", "Web < 1MB"). **Effort**: S.

#### Conversion History / Recents
Re-access recent outputs and re-run a previous conversion. **Effort**: M.

#### iPad Optimization
Proper split-view layout and drag-and-drop. **Effort**: M.

#### Additional Formats
TIFF/BMP/GIF output; PDF→image extraction. **Effort**: M.

---

### Could Have (v2.0+)

#### App Intents / Shortcuts Actions
Expose HeicSwap conversion as Shortcuts actions so power users automate it — turns the "Sherlock" threat into a distribution surface. Deferred: not needed to win the mainstream persona. **Effort**: M.

#### Batch Rename on Export
Pattern-based renaming of converted files. Deferred: nice-to-have. **Effort**: S.

#### Video Conversion (HEVC → MP4)
Natural engine extension, but larger scope and different keyword cluster. Likely its own app. Deferred.

---

### Won't Have (Out of Scope)

| Feature | Reason |
|---------|--------|
| Server/cloud conversion | Violates the on-device privacy wedge — the whole point |
| Accounts / sign-in | Adds friction & liability for a utility; nothing to sync |
| Ads | Off-brand; ad-supported incumbents are who we beat |
| Photo editing (filters, crop, retouch) | Scope discipline — we convert, not edit |
| Timed fake "free trial" / weekly-as-default | Dark pattern; contradicts the honest-pricing positioning |
| Android / web app | iOS-native focus for v1 |

---

## 4. User Flows

### Onboarding (first launch)
```
[Launch] → [1: "Convert any photo — HEIC, RAW, PNG → JPG, PDF"]
→ [2: "100% on your iPhone. Nothing is ever uploaded."]
→ [3: "Add photos to start"] → [Home (Empty State)]
   ↳ Skip at any point → [Home (Empty State)]
```

### Core Loop
```
[Home] → (Add Photos / Import) → [Convert Queue]
→ (Choose format / PDF / resize / strip toggle) → (Convert)
→ [Progress] → [Results] → (Save to Photos / Files / Share) → [Home]
```

### Monetization Flow
```
(Convert beyond daily cap)  ─┐
(Tap Pro feature: RAW/WebP/PDF/resize) ─┤→ [Paywall: $9.99/yr default · $1.99/wk · $19.99 lifetime · Restore]
                              │      → (Purchase) → [Unlocked, continue conversion]
                              │      → (Dismiss)  → [Continue with remaining free allowance]
```

### Settings Flow
```
[Home] → (Settings) → [Default format/quality · Metadata default · Manage/Restore subscription · Privacy · Terms]
```

---

## 5. Analytics & Events

### Key Events
| Event | Trigger | Parameters |
|-------|---------|-----------|
| `app_launched` | App opens | `is_first_launch` |
| `onboarding_completed` | Finishes/skips onboarding | `screens_viewed`, `skipped` |
| `images_imported` | Items added to queue | `count`, `source` (photos/files/share_ext) |
| `conversion_started` | User taps Convert | `count`, `source_format`, `target_format`, `is_batch`, `used_resize`, `used_strip_exif`, `to_pdf` |
| `conversion_completed` | Batch finishes | `count_success`, `count_failed`, `duration_ms` |
| `daily_cap_reached` | Free cap hit | `cap_value` |
| `paywall_shown` | Paywall presented | `trigger` (cap / pro_feature_raw / pro_feature_pdf / pro_feature_resize / etc.) |
| `purchase_completed` | Purchase succeeds | `product_id` (annual/weekly/lifetime), `price` |
| `output_saved` | Save/share | `destination` (photos/files/share) |
| `share_extension_used` | Convert via extension | `target_format` |

### Funnels
1. **Activation**: launch → images_imported → conversion_completed
2. **Monetization**: paywall_shown → purchase_completed (segment by `trigger`)

### A/B Test Candidates
- Daily free cap: **N = 5 vs 10 vs 15**
- Paywall default-highlight: **annual vs lifetime**
- Onboarding length: 3 screens vs 1 screen

---

## 6. Technical Architecture (Tech Lead addendum)

> Designed around the **post-review v1** (RAW, WebP-encode, and the Share Extension deferred to v1.1 per Critical 3; value-gating per Critical 1; privacy-first analytics per Critical 2). Net effect: a smaller, lower-risk, dependency-light build whose entire stack is consistent with the on-device privacy promise.

### 6.1 Architecture assessment

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Language | Swift 6, strict concurrency | Conventions; the conversion engine is concurrency-heavy (batch) — strict checking prevents data races early |
| UI | SwiftUI | Single-screen utility; native components (`PhotosPicker`, `.sheet` detents, `ShareLink`) cover the whole flow |
| Architecture | MVVM + `@Observable` | iOS 17 Observation; thin views, a `ConversionEngine` service, per-screen view models |
| Data | Minimal v1 (`AppStorage` + small store); **SwiftData in v1.1** | v1 only persists settings + entitlement cache; SwiftData arrives with history/presets to avoid premature schema |
| Conversion | **ImageIO** (`CGImageSource`/`CGImageDestination`) + **Core Image** (resize) + **PDFKit** | 100% native, on-device, no dependency; ImageIO gives precise metadata control for EXIF-strip |
| Monetization | RevenueCat | Conventions; offline entitlement cache |
| Analytics | **TelemetryDeck** (privacy-first, EU/GDPR, anonymized on-device) | Resolves Critical 2 — keeps the “we never collect your photos / no personal data” claim **literally true** |
| Crash | **MetricKit** (Apple, on-device) | No third-party data egress; keeps the privacy label clean |
| Min iOS | **iOS 26.0** | Latest-only per direction — adopts Liquid Glass + the newest ImageIO/SwiftUI and drops all back-compat cost. Tradeoff vs the install-volume thesis (narrower base) is accepted |
| CI/CD | Fastlane + GitHub Actions | Conventions |

**Dependency audit** — lean by design (privacy app = fewer phone-home SDKs):

| Package | Purpose | Risk | Native alternative |
|---------|---------|------|--------------------|
| RevenueCat | Subscriptions/IAP | Low | StoreKit 2 direct (more work; keep RC) |
| TelemetryDeck | Privacy-first product analytics | Low | MetricKit only (less product insight) |
| — (no Firebase) | removed per Critical 2 | — | — |
| — (no libwebp in v1) | WebP-encode deferred to v1.1 | — | verify ImageIO WebP-encode before adding |

Two dependencies for v1. Conversion, PDF, resize, and metadata-strip are all Apple frameworks.

### 6.2 Data model sketch

```swift
// Output formats shipping in v1 (RAW input + WebP output land in v1.1)
enum OutputFormat: String, CaseIterable, Sendable {
    case jpg, png, heic, pdf            // webp -> v1.1
    var isPro: Bool { false }           // no v1 output is inherently Pro; gating is batch-size + advanced features

}

enum ResizeMode: Sendable, Equatable {
    case none
    case maxDimension(Int)              // e.g. 2048 px
    case targetBytes(Int)               // e.g. 2_000_000 -> binary-search quality
}

struct ConversionOptions: Sendable {
    var target: OutputFormat = .jpg
    var quality: Double = 0.9
    var resize: ResizeMode = .none
    var stripMetadata: Bool = false     // Pro
}

struct SourceItem: Identifiable, Sendable {
    let id: UUID
    let assetID: String?                // PHAsset identifier, if from Photos
    let fileURL: URL?                   // if imported from Files
    var status: ItemStatus = .pending   // pending / downloading / converting / done / failed
}

// The engine is an actor — bounded concurrency, no data races on shared progress
actor ConversionEngine {
    func convert(_ items: [SourceItem], _ opts: ConversionOptions,
                 progress: @Sendable (UUID, ItemStatus) -> Void) async throws -> [URL]
}

// Entitlement is cached so paid users work fully offline
struct Entitlement { var isPro: Bool; var source: String /* annual/lifetime */ }
```

**Value-gating (resolves Critical 1 — gate the value moment, not a daily count):**

```swift
enum ProGate { case freeBatchLimit(Int)  // free converts up to N images at once
               , pdf, resizeToBytes, stripMetadata, rawInput, webpOutput /* v1.1 */ }

func requiresPro(_ items: [SourceItem], _ o: ConversionOptions) -> Bool {
    items.count > FREE_BATCH_LIMIT            // FREE_BATCH_LIMIT ≈ 5 (A/B candidate)
    || o.stripMetadata
    || { if case .targetBytes = o.resize { return true }; return false }()
}
// Free = basic conversion AND small image→PDF at small batch (PDF is our top acquisition term).
// Pro  = large batch, resize-to-size, strip-metadata (+ RAW/WebP in v1.1).
// No daily counter to persist — the gate is feature/size-based.
```

### 6.3 Technical risk register

| Risk | Likelihood | Impact | Mitigation |
|------|:---:|:---:|------------|
| iCloud-optimized originals need download (Critical 4) | High | High | `PHImageManager` with `isNetworkAccessAllowed = true` + `progressHandler`; explicit “Downloading from iCloud…” state; copy says **“never uploaded / no server conversion”** (always true), not “works offline” |
| Large-batch / large-image memory pressure | Med | High | `actor` engine, bounded `TaskGroup` (2–4 parallel), `autoreleasepool` per item, downsample-on-load (`kCGImageSourceThumbnailMaxPixelSize`), stream to temp, release immediately |
| EXIF/GPS strip incorrectness | Med | High (brand) | ImageIO destination written **without** copying source properties; unit test asserts no GPS/EXIF dict in output |
| Privacy claim contradicted by egress | Low | High (brand) | No image bytes/filenames in any analytics; **CI test asserting zero network during a conversion**; RevenueCat/TelemetryDeck calls audited |
| Temp-file accumulation fills storage | Med | Med | Convert into a dedicated temp dir; purge on results-dismiss and app background |
| WebP **encode** unsupported by ImageIO (v1.1) | Med | Med | Verify ImageIO encode before committing; else add libwebp — **deferred, not in v1** |
| RAW memory/CR3 gaps at 100-batch (v1.1) | Med | Med | `CIRAWFilter` with serial processing + downsample — **deferred to v1.1** |
| Share-extension memory limits (v1.1) | High | Med | Extension does light single/small jobs only; hand heavy batches to the main app via App Group — **deferred to v1.1** |

### 6.4 Implementation roadmap (leaner v1, ~4–5 weeks solo)

| Phase | Scope | Size |
|-------|-------|:---:|
| **0 · Foundation** | Project, Swift 6 concurrency baseline, DI, Warm Darkroom design tokens, navigation shell | S–M |
| **1 · Engine** | ImageIO convert (HEIC/PNG/JPG/HEIC), strip-metadata, Core Image resize (maxDim + target-bytes), unit + zero-egress tests | L |
| **2 · Import & batch** | `PhotosPicker` + Files import, queue UI, `actor` batch with bounded concurrency, **iCloud-download handling** | L |
| **3 · PDF** | Image→multi-page PDF (PDFKit), page reorder | M |
| **4 · Monetization** | RevenueCat (annual + lifetime), **value-gating**, honest paywall, offline entitlement cache | M–L |
| **5 · Shell & identity** | Onboarding (3), Settings, empty/error states, Warm Darkroom UI, “developing” animation (+ Reduced-Motion crossfade) | M–L |
| **6 · Polish** | TelemetryDeck + MetricKit, accessibility pass, App Store metadata + accurate privacy label | M |
| **v1.1 fast-follow** | RAW input, WebP-encode, Share Extension, history/presets (SwiftData), iPad | — |

### 6.5 App Store review risks

- **Guideline 4.3 (spam/duplicate utility)** — *the real risk for converters.* Mitigation: the distinct Warm Darkroom identity + a genuine multi-feature set (PDF, resize-to-size, strip-metadata, batch) + quality make it clearly not a template clone. Ensure the listing/screenshots read as original.
- **Privacy nutrition label** — must match actual collection. With TelemetryDeck (anonymized, no personal data) + MetricKit + zero image egress, “Data Not Collected / Not Linked to You” is defensible. Audit before submission.
- **Subscriptions (3.1.2)** — restore purchases, manage-subscription link, clear pricing/terms — all in Settings/paywall by design; no dark patterns. **Recommend dropping the weekly** (Critical 5) to also sidestep utility-subscription scrutiny.
- **Photos permission strings** — accurate purpose strings (add-only for save; PHPicker needs none for import).

### 6.6 Performance considerations

- **Launch:** < 1s to interactive — defer RevenueCat/TelemetryDeck init off the launch critical path.
- **Throughput target:** 12-photo HEIC→JPG batch < ~3s on a recent device; 100-photo batch completes without a memory crash (validated on an older target device, e.g. iPhone 12).
- **Memory:** downsample-on-load, bounded concurrency, per-item `autoreleasepool`; never hold the full batch decoded in memory.
- **App size:** target < 15 MB — the lean dependency set is a feature (explicitly counters the 173 MB incumbent).
- **Offline:** conversion never touches the network; paid entitlement cached for offline use.

---

## 7. App Store Metadata

### App Name (≤30 char)
**Primary**: `Image Converter — HeicSwap` (26 char) — leads with the head keyword, keeps the brand.
**Alternatives**: `HeicSwap: HEIC to JPG & PDF`, `HeicSwap — Image Converter`.

### Subtitle (≤30 char)
`HEIC to JPG, PDF & Resize` (25 char)

### Keywords (≤100 char, comma-separated, no spaces)
`heic,jpg,png,webp,raw,convert,image,photo,pdf,resize,compress,size,format,batch,jpeg,heif,converter`

### Category
**Primary**: Photo & Video · **Secondary**: Utilities

### Description Strategy
Lead with the three honest promises (on-device/private · no ads · no weekly trap), then the format breadth (HEIC/RAW/WebP → JPG/PNG/PDF), then batch + resize-to-size. Explicitly contrast with cloud uploaders.

### Screenshot Strategy
| # | Screen | Caption |
|---|--------|---------|
| 1 | Convert result + privacy badge | "Your photos never leave your iPhone" |
| 2 | Batch queue converting | "Convert your whole album in one tap" |
| 3 | Format grid (HEIC/RAW/WebP→JPG/PNG) | "Every format. Even RAW & WebP." |
| 4 | Image→PDF | "Turn photos into one PDF" |
| 5 | Resize-to-size + pricing honesty | "Shrink to fit. $9.99/yr or own it forever." |

---

## 8. Release Plan

### v1.0 (MVP) — Target: Week 6
Must-Have features 3.1–3.11.
| Block | Features | Effort |
|-------|----------|--------|
| Engine | 3.2 conversion, 3.5 resize, 3.6 strip | L + M + S |
| Flow | 3.1 import, 3.3 batch, 3.4 PDF, 3.7 output | M + M + M + S |
| Monetization | 3.8 paywall + cap | L |
| Reach | 3.9 share extension | M |
| Shell | 3.10 onboarding, 3.11 settings | S + S |

**Total estimated effort**: ~4–6 weeks solo.

### v1.1 — Target: 2–3 weeks post-launch
Files/Action extension, output presets, history, iPad, extra formats.

### v2.0 — If traction warrants
App Intents/Shortcuts actions, batch rename; evaluate video conversion as a sibling app.

---

## 9. Open Questions

| # | Question | Owner | Status |
|---|----------|-------|--------|
| 1 | Exact free vs Pro split — is the free tier "N/day any format" or "N/day basic formats only, RAW/WebP/PDF always Pro"? | PM + Strategist | Open |
| 2 | Does iOS encode WebP natively, or do we need a lightweight dependency? | Tech Lead | **Resolved** — WebP-encode deferred to v1.1; verify ImageIO encode, else add libwebp |
| 3 | Default free **batch** size (N) before Pro? (value-gate, not daily cap) | PM | Open (lean 5) |
| 4 | Lifetime at $19.99 — confirm it doesn't suppress annual too much; validate with first-30-day data | Strategist | Open |
| 5 | Minimum iOS version? | Tech Lead | **Resolved — iOS 26.0** (latest-only; Liquid Glass + newest APIs; reach tradeoff accepted) |

---

## 10. Devil's Advocate Review Summary
_To be completed in Stage 4._

**Score**: [X/10]
**Critical Issues Resolved**: [List]
**Accepted Risks**: [List with rationale]
