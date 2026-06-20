# PRD: HeicSwap — Image Converter

> **Version**: v1.0 (Locked)
> **Date**: 2026-06-19
> **Status**: Approved — ready for `/dev-tasks`
> **Author**: Product Team (AI-assisted) · Strategist → PM → Designer → Critic → Tech Lead → PM (final)
> **Source docs**: `discovery-heicswap.html` (8.0/10 BUILD) · `design-HeicSwap.html` (Warm Darkroom) · `review-HeicSwap.html` (7/10)

---

## Changelog

| Version | Date | Changes | Triggered By |
|---------|------|---------|-------------|
| v0.9 | 2026-06-19 | Initial draft PRD | Discovery + pricing |
| v0.95 | 2026-06-19 | Tech Lead architecture (§6) | Tech assessment |
| **v1.0** | 2026-06-19 | **Final scope locked: all 5 critical issues resolved, v1 trimmed, KPIs reset** | Critic review + final assembly |

### What changed in v1.0 (critic resolutions)
1. **Free tier re-architected** — value-gated (batch size + Pro features), not a daily cap.
2. **Privacy stack fixed** — TelemetryDeck + MetricKit (no Firebase); privacy copy made literally true.
3. **Scope trimmed** — RAW, WebP-encode, Share Extension moved to v1.1; v1 = the mainstream core.
4. **Privacy/offline copy corrected** — “never uploaded · no server conversion” + iCloud-download handling.
5. **Pricing decision** — weekly kept but transparent & secondary, annual is the default; **drop-weekly is flagged as a one-line option** (see §11). KPI reset from retention to revenue-per-install.

---

## 1. Product Overview

### One-Liner (App Store subtitle, ≤30 char)
**`PDF, Resize & Compress Photos`**

### Problem Statement
Every iPhone shoots HEIC, so users constantly hit a wall — a site rejects the photo, an Android friend can’t open it, a form caps the file size, or they need photos as one PDF. The apps that solve this today either **upload private photos to a server**, **bury the task in ads**, or **spring a surprise weekly sub** — and Apple’s Files/Shortcuts path is invisible to mainstream users and can’t do PDF, resize-to-size, RAW, or WebP.

### Vision
In 12 months, HeicSwap is the **default “just make it a normal file” app** — fast, genuinely private (no server, ever), ad-free, honestly priced — and the proven on-device file/media engine behind sibling utilities (SizeFit, UnzipX).

### Target Audience
- **Primary — “Blocked Sender”**: 20–55, non-technical, doesn’t know Shortcuts exists; needs a normal JPG / smaller file / a PDF *right now*. Maps to the head keywords.
- **Secondary — “Prosumer / RAW shooter”**: wants RAW→JPG, WebP, batch control; supplies recurring-use revenue. **Served in v1.1.**

### Anti-Goals — what HeicSwap explicitly does NOT do
- **No server/cloud conversion, no accounts.** All conversion on-device. (The differentiator.)
- **No ads.**
- **No third-party data collection of your content.** Anonymous usage stats only, EU/GDPR-clean.
- **No photo editing** beyond resize/compress.
- **No dark patterns** — no fake trial, no one-photo tease, no pre-selected weekly, no fake countdowns.
- **No Android/web** for v1.

---

## 2. Goals & Success Metrics

### Primary KPI
**Revenue per install (RPI)** — the right metric for a high-volume, partly single-use utility. Internal launch target: **RPI ≥ $0.08** (blend of $9.99 annual, $19.99 lifetime, $1.99 weekly), refined after first 30 days.

### Secondary KPIs
| Metric | Target | Measurement |
|--------|--------|-------------|
| Free→Paid conversion (blended) | ≥ 3.5% of activated users | RevenueCat |
| Activation (≥1 successful conversion, first session) | > 80% | TelemetryDeck |
| Paywall view → purchase | > 6% | RevenueCat |
| App Store rating | > 4.6 | App Store Connect |
| 30-day repeat usage (directional, not a goal) | ~12–15% | TelemetryDeck |
| Crash-free sessions | > 99.5% | MetricKit |
| Refund rate | < 2% | App Store Connect |

> KPI note (Critic-driven): retention is **not** the optimization target for a utility. Track repeat usage as a signal; optimize RPI and conversion.

---

## 3. Feature Specification (MoSCoW)

### Must Have — MVP v1.0

#### 3.1 Photo & File Import — `Effort: M`
**User Story**: As a Blocked Sender, I want to pick photos or files fast, so I can start converting without hunting.
**Acceptance Criteria**:
- [ ] Tapping “Add Photos” opens `PhotosPicker` with multi-select (no full-library permission).
- [ ] “Import from Files” opens the document picker filtered to supported image types.
- [ ] Selected items appear as ordered thumbnails in a convert queue.
- [ ] Unsupported files are flagged inline (“Can’t convert this type”) and skipped, never crash.
- [ ] **iCloud-optimized originals** show a “Downloading from iCloud…” state and fetch via `PHImageManager` (`isNetworkAccessAllowed = true`) before converting.

#### 3.2 On-Device Conversion Engine — `Effort: L`
**User Story**: As a user, I want conversion entirely on my device, so my photos stay private and it works without a server.
**Acceptance Criteria**:
- [ ] Input HEIC/HEIF, PNG, JPG → output **JPG, PNG, HEIC** runs 100% on-device (ImageIO), no network call.
- [ ] Color profile preserved; no visible quality loss at “High”.
- [ ] With no network (originals already local), conversion succeeds.
- [ ] A CI test asserts **zero network egress** during a conversion.
**Notes**: RAW input and WebP output are **v1.1** (see Should Have).

#### 3.3 One-Tap Batch — `Effort: M`
**User Story**: As a Blocked Sender, I want a whole batch converted in one tap.
**Acceptance Criteria**:
- [ ] All queued items convert in one action with per-item progress and the “developing” reveal.
- [ ] 100+ item batch stays responsive and memory-bounded (bounded concurrency, downsample-on-load).
- [ ] One item failing doesn’t abort the batch; it’s reported with Retry.
**Notes**: Free up to a small batch size; larger batches are Pro (see 3.8).

#### 3.4 Image → Multi-Page PDF — `Effort: M` · **Free within the free batch** (Pro only for larger batches)
**User Story**: As a form-filler, I want to combine photos into one PDF.
**Acceptance Criteria**:
- [ ] 2+ images → single multi-page PDF, one image per page, in queue order; pages reorderable.
- [ ] Single image → valid one-page PDF.

#### 3.5 Resize / Compress to Target — `Effort: M` · target-size is **Pro**
**User Story**: As a Blocked Sender, I want to shrink a photo under a size limit so a form accepts it.
**Acceptance Criteria**:
- [ ] Set max dimension (px) **or** target file size (e.g. “under 2 MB”); output respects it.
- [ ] Target file size iterates encoder quality to land at/under target; resulting size reported.
- [ ] Presets: “Web < 2MB”, “Email”, “Original”.

#### 3.6 Strip EXIF / Location — `Effort: S` · **Pro**
**Acceptance Criteria**:
- [ ] When ON, output contains no GPS/EXIF/maker-note data (unit test verifies).
- [ ] When OFF (default), metadata preserved. Setting persists.

#### 3.7 Output & Sharing — `Effort: S`
**Acceptance Criteria**:
- [ ] Save to Photos (add-only permission), Save to Files, or system Share for the whole batch.
- [ ] Post-conversion screen is one tap from done.

#### 3.8 Value-Gated Paywall (RevenueCat) — `Effort: L`
**User Story**: As the business, I want a generous free tier that converts at the moment of real need, without dark patterns.
**Acceptance Criteria**:
- [ ] **Free**: unlimited basic conversion (HEIC/PNG/JPG/HEIC) up to **N images per batch** (launch N≈5, A/B candidate), watermark-free, ad-free.
- [ ] **Pro gates**: batch > N (conversion *or* PDF), resize-to-target-size, strip-metadata (and RAW/WebP in v1.1). **Small image→PDF is free** within the free batch — it's our top acquisition term, so it must not paywall on first use.
- [ ] Hitting a gate shows the paywall: **Annual $9.99 (default-highlighted “Best value”)**, **Lifetime $19.99**, **Weekly $1.99 (secondary, “cancel anytime”)**, plus Restore.
- [ ] Purchase unlocks immediately; entitlement cached so paid users work fully offline.
- [ ] Dismissing the paywall keeps the user in the free tier; no nags, no fake timers.

#### 3.9 Onboarding — `Effort: S`
**Acceptance Criteria**:
- [ ] ≤3 skippable screens: value → privacy promise (“never uploaded”) → “Add photos to start”.
- [ ] No account, no paywall during onboarding. Ends on a usable home/empty state.

#### 3.10 Settings — `Effort: S`
**Acceptance Criteria**:
- [ ] Default format/quality, default metadata-strip, Manage/Restore subscription, accurate privacy statement, Terms.
- [ ] Privacy statement is **literally true** (“Your photos and files are never collected or uploaded; we use anonymous usage stats to improve the app”).

---

### Should Have — v1.1 (fast-follow)
- **RAW input** (DNG/CR2/NEF/ARW via `CIRAWFilter`) — serial + downsampled. `Effort: L`
- **WebP output** — verify ImageIO encode, else libwebp. `Effort: M`
- **Share Extension** — light single/small conversions; heavy jobs handed to the main app. `Effort: M`
- **Conversion history & presets** (SwiftData). `Effort: M`
- **Files / Action extension** + **iPad** optimization. `Effort: M`

### Could Have — v2.0+
- App Intents / Shortcuts actions (turn the “Sherlock” threat into a distribution surface).
- Batch rename on export. · Video conversion (HEVC→MP4) — likely a sibling app.

### Won't Have (out of scope)
| Feature | Reason |
|---------|--------|
| Server/cloud conversion | Violates the on-device wedge |
| Accounts / sign-in | Friction + liability; nothing to sync |
| Ads | Off-brand; ad apps are who we beat |
| Third-party content analytics | Contradicts the privacy promise |
| Photo editing (filters/crop/retouch) | Scope discipline |
| Fake trial / weekly-as-default | Dark pattern; against the brand |

---

## 4. User Flows

### Onboarding
```
[Launch] → [1 · "Convert any photo"] → [2 · "Developed on your device. Never uploaded."]
        → [3 · "Add photos to start" → add-only Photos prompt] → [Home · Empty]
            ↳ Skip (top-right) anytime → [Home · Empty]
```
### Core Loop
```
[Home/Empty] → (Add Photos / Files) → [Queue]  (iCloud? → "Downloading…")
   → (format · resize · PDF · strip) → (Convert) → [Developing…] → [Results]
   → (Save Photos / Save Files / Share) → [Home]      ↳ (Cancel) → [Home · queue intact]
```
### Monetization (value-gate, not daily cap)
```
(Batch > N)  ─┐
(Tap resize-to-size / strip) ──────┤→ [Paywall: Annual $9.99 default · Lifetime $19.99 · Weekly $1.99 · Restore]
                                    │      → (Buy) → [unlock, continue]
                                    │      → (Dismiss) → [continue free, no nag]
```
### Error
```
[Convert] → (item fails) → [Results: item flagged + Retry, rest succeed]
[Import]  → (unsupported) → [inline "Can't convert this", skipped]
[Convert] → (no network + iCloud-only original) → ["Connect to download from iCloud" — never an upload]
```

---

## 5. Design (summary — full spec: `design-HeicSwap.html`)

**Direction: Warm Darkroom** — dark-first, photographic, safelight-amber accent, serif display titles, system-sans body. Personality lives in the chrome/empty-states/“developing” animation; the conversion flow stays crisp.

| Token | Light | Dark (hero) |
|-------|-------|------|
| Background | `#FBF3EC` | `#1A1413` |
| Surface | `#FFFDF9` | `#251B18` |
| Primary text | `#2A1F1A` | `#F4EBE3` |
| Accent (safelight) | `#D9542F` | `#FF7B54` |
| Accent-2 | `#E84B3C` | `#E84B3C` |

- **Signature**: thumbnails “develop” from dark→full color as each finishes (Reduced-Motion → crossfade).
- **Persistent trust badge** `⛊ On-device` on Home, Developing, Results **and** the Paywall.
- Typography: serif titles via `.font(.system(.largeTitle, design: .serif))`; CTA uses dark text on amber (never white). Full AA contrast pairs in the design spec. Dark mode is the hero; light = Warm Paper.

---

## 6. Technical Architecture

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Language / UI | Swift 6 (strict concurrency) · SwiftUI | Native single-screen utility |
| Architecture | MVVM + `@Observable` | Thin views + a `ConversionEngine` actor |
| Min iOS | **26.0** | Latest-only (per direction): adopts Liquid Glass + newest ImageIO/SwiftUI, no back-compat cost. Tradeoff: narrower install base than the volume thesis — accepted |
| Conversion | ImageIO + Core Image + PDFKit | 100% native, on-device, precise metadata control |
| Data | `AppStorage` (v1) → SwiftData (v1.1 history/presets) | No premature schema |
| Monetization | RevenueCat (annual + lifetime + weekly) | Offline entitlement cache |
| Analytics / Crash | **TelemetryDeck** (anonymized, GDPR) + **MetricKit** | Keeps the privacy claim true — no Firebase |
| CI/CD | Fastlane + GitHub Actions | — |

**Dependencies (2):** RevenueCat (Low), TelemetryDeck (Low). No Firebase. No libwebp in v1.

**Value-gating (core logic):**
```swift
func requiresPro(_ items: [SourceItem], _ o: ConversionOptions) -> Bool {
    items.count > FREE_BATCH_LIMIT       // ≈5 — applies to conversion AND PDF
    || o.stripMetadata
    || { if case .targetBytes = o.resize { return true }; return false }()
}   // image→PDF is FREE within the free batch (our top acquisition term). No daily counter.
```

**Engine sketch:**
```swift
actor ConversionEngine {                 // bounded concurrency, no shared-state races
    func convert(_ items: [SourceItem], _ opts: ConversionOptions,
                 progress: @Sendable (UUID, ItemStatus) -> Void) async throws -> [URL]
}
```

**Top technical risks & mitigations** (full register in draft §6.3):
| Risk | Mitigation |
|------|------------|
| iCloud-optimized originals need download | `PHImageManager` + progress + “Downloading…” state; copy = “never uploaded” |
| Large-batch memory | actor + bounded `TaskGroup` + `autoreleasepool` + downsample-on-load + temp + purge |
| EXIF-strip correctness | Write destination without copying properties; unit test asserts no GPS |
| Privacy claim vs egress | No content in analytics; CI zero-egress test |

**Roadmap (~4–5 wks):** 0 Foundation → 1 Engine(+tests) → 2 Import/batch(+iCloud) → 3 PDF → 4 Paywall/gating → 5 Shell+Warm-Darkroom UI → 6 Analytics/polish/metadata. v1.1: RAW, WebP, Share Extension, history, iPad.

**App Store risks:** Guideline **4.3 (duplicate utility)** is the real one — mitigated by the distinct Warm Darkroom identity + genuine feature set; accurate privacy nutrition label (Data Not Collected); subscription compliance (restore + manage link, no dark patterns).

**Performance:** launch < 1s (defer SDK init); 12-photo batch < ~3s; 100-photo batch crash-free on iPhone 12; app size < 15 MB.

---

## 7. Analytics & Events (TelemetryDeck — no content, no PII)

| Event | Trigger | Parameters |
|-------|---------|-----------|
| `app_launched` | Open | `is_first_launch` |
| `onboarding_completed` | Finish/skip | `screens_viewed`, `skipped` |
| `images_imported` | Added to queue | `count`, `source` (photos/files) |
| `icloud_download` | Optimized originals fetched | `count` |
| `conversion_completed` | Batch done | `count_success`, `count_failed`, `target_format`, `is_batch`, `used_resize`, `used_strip`, `to_pdf`, `duration_ms` |
| `pro_gate_hit` | Pro feature/size tapped | `gate` (batch_size/resize_bytes/strip) |
| `paywall_shown` | Paywall presented | `trigger` |
| `purchase_completed` | Purchase | `product_id` (annual/lifetime/weekly) |
| `output_saved` | Save/share | `destination` |

**Funnels**: Activation (launch→import→conversion_completed); Monetization (pro_gate_hit→paywall_shown→purchase, segmented by `gate`/`trigger`).
**A/B candidates**: `FREE_BATCH_LIMIT` (3 vs 5 vs 8); paywall default (annual vs lifetime); onboarding length.

---

## 8. App Store Metadata

> Built on **live Astro (US)** keyword data — the seed’s figures were stale (“image converter” is pop **7**, not 55). The ASO anchor is the **PDF conversion cluster**, not “image converter.”

- **Name (≤30):** `HeicSwap: Image Converter` (brand + category; indexes heic, image, converter)
- **Subtitle (≤30):** `PDF, Resize & Compress Photos` (indexes the high-volume pdf/compress terms the name misses)
- **Keywords (≤100):** `jpg,png,convert,pictures,compressor,metadata,remover,batch,size,maker,photos,shrink` (73/100; no stop-words, no repeats of name/subtitle)
- **Category:** Photo & Video / Utilities
- **Best entry terms (pop/diff, US):** convert image to pdf (38/23) · jpg to pdf (57/43) · heic converter (22/23) · convert heic (16/21) · photo compressor (32/39) · zero-competition EXIF terms — metadata remover / exif stripper (diff 21).
- **Avoid early:** photo to pdf (62/73) · pdf converter (60/66) · image size (45/55) · image to pdf (45/54) — high volume but difficulty 54+ for a new app.
- **Description:** lead with the three honest promises (on-device/private · no ads · no weekly trap) → **PDF + batch + compress/resize-to-size** → format breadth → contrast with cloud uploaders.
- **Screenshots (5):** 1 privacy badge “never leaves your iPhone” · 2 **image→PDF “photos into one PDF”** (top acquisition term) · 3 batch “whole album in one tap” · 4 format breadth · 5 resize-to-size + “fair pricing, own it forever”.

---

## 9. Release Plan

- **v1.0 (MVP) — Week ~5:** §3.1–3.10. ~4–5 weeks solo.
- **v1.1 — 2–3 weeks post-launch:** RAW, WebP output, Share Extension, history/presets, iPad. *(These are the deferred Must-Haves; ship fast to serve the prosumer persona and widen ASO.)*
- **v2.0 — if traction:** App Intents/Shortcuts, batch rename; evaluate video sibling.

---

## 10. Open Questions

| # | Question | Owner | Status |
|---|----------|-------|--------|
| 1 | `FREE_BATCH_LIMIT` launch value (3/5/8) | PM | Open — lean 5, then A/B |
| 2 | Keep the $1.99 weekly, or drop it for a “no weekly subscriptions, ever” headline? | PM + Strategist | **Decision flagged for you** (§11) |
| 3 | Lifetime $19.99 vs annual $9.99 mix — validate at day 30 | Strategist | Open — validation checkpoint set |
| 4 | WebP encode: ImageIO vs libwebp | Tech Lead | Open — verify in v1.1 |
| 5 | Should small image→PDF be free (within `FREE_BATCH_LIMIT`) so we don’t paywall our top acquisition term? | PM + Strategist | **Resolved — YES.** PDF free within the free batch; Pro = large batch + resize-to-size + strip + RAW/WebP |

---

## 11. Devil's Advocate Review Summary

**Pre-fix score:** 7/10. **All 5 critical issues resolved or consciously accepted:**

| # | Critical issue | Resolution |
|---|----------------|-----------|
| 1 | Free tier too generous (daily cap) | ✅ Re-architected to **value-gating** (batch size + PDF/resize/strip) |
| 2 | Privacy brand vs Firebase + false copy | ✅ **TelemetryDeck + MetricKit**, no Firebase; copy made literally true |
| 3 | v1 front-loads riskiest features | ✅ **RAW/WebP/Share-extension → v1.1**; v1 = mainstream core |
| 4 | “Never leaves phone/offline” breaks on iCloud | ✅ Copy → “never uploaded”; **iCloud-download state** added |
| 5 | $1.99 weekly: review risk + thin MRR | ⚠️ **Kept, transparent & secondary** (annual default) — **drop-weekly offered as a one-line option** |

**Accepted risks (conscious):**
- **Guideline 4.3 (duplicate utility):** accepted with mitigation (distinct design + genuine feature depth). Standard for the category.
- **Single-use churn ceiling on MRR:** accepted by design — monetized via lifetime + install volume; **validation checkpoint:** if free→paid < 2% after 4 weeks at meaningful install volume, revisit `FREE_BATCH_LIMIT` / gates before scaling spend.
- **Time-boxed winnability:** accepted — first-90-day land-grab (fast review accumulation + ASA on tail terms).

**Other incorporated feedback:** KPI shifted to revenue-per-install; ASO sequenced to the winnable tail first; temp-file cleanup, support destination, and serif Dynamic-Type checks added to the build.
