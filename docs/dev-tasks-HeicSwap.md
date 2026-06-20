# Development Tasks: HeicSwap

> **Generated**: 2026-06-20
> **Source PRD**: docs/PRD-HeicSwap-v1.md
> **Notion version page**: [🚀 1.0.0 MVP](https://app.notion.com/p/385be5ec9ff6813c8e86d18d802a1b95)
> **App page**: [📱 HeicSwap](https://app.notion.com/p/384be5ec9ff68039b40dead9031ddb4f)
> **Version / Sprint**: 1.0.0 MVP
> **Status**: Active

---

## Summary

| Metric | Value |
|--------|-------|
| Total tasks | 29 |
| Phases | 12 |
| Estimated effort | ~5–6 weeks (solo) |
| Must Have features covered | Import · On-device engine · Batch · Image→PDF · Resize/compress · EXIF strip · Output/Share · Value-gated paywall · Onboarding · Settings |
| Deferred to v1.1 | RAW input · WebP output · Share Extension · history/presets · iPad |

| Phase | Tasks | Effort |
|-------|-------|--------|
| 1 – Setup | 3 | M+S+M |
| 2 – Data Model | 2 | S+S |
| 3 – Services | 5 | M+M+S+M+M |
| 4 – Shell | 1 | M |
| 5 – Features | 5 | M+M+M+M+S |
| 6 – Monetization | 3 | M+M+S |
| 7 – Onboarding | 1 | M |
| 8 – Settings | 1 | M |
| 9 – Analytics | 1 | M |
| 10 – Polish | 4 | M+M+M+S |
| 11 – App Store | 1 | M |
| 12 – Testing | 2 | M+S |

---

## Phase 1: Setup

### 1.1 — Scaffold Xcode project (Swift 6, iOS 26)
**Notion**: https://app.notion.com/p/385be5ec9ff6817ab296df8605d6a329
**Effort**: M | **Priority**: High | **Dependencies**: None
**Overview**: Stand up the project — Swift 6 strict concurrency, iOS 26 min target, MVVM folder structure.

### 1.2 — Add SwiftPM deps (RevenueCat, TelemetryDeck)
**Notion**: https://app.notion.com/p/385be5ec9ff681d7a9b3c999974de58e
**Effort**: S | **Priority**: High | **Dependencies**: 1.1
**Overview**: Add the only two dependencies behind thin protocol wrappers; config-based keys; deferred init. No Firebase.

### 1.3 — Build Warm Darkroom theme
**Notion**: https://app.notion.com/p/385be5ec9ff6815bb1c4ea202f7694e5
**Effort**: M | **Priority**: High | **Dependencies**: 1.1
**Overview**: Reusable design tokens — light/dark palettes, serif type scale, spacing, radii, safelight gradient. CTA = dark-on-amber.

---

## Phase 2: Data Model

### 2.1 — Define core models & enums
**Notion**: https://app.notion.com/p/385be5ec9ff681e2b753c0f0d10ecc46
**Effort**: S | **Priority**: High | **Dependencies**: 1.1
**Overview**: Sendable value types: OutputFormat, ResizeMode, ConversionOptions, SourceItem/ItemStatus, Entitlement. No format inherently Pro.

### 2.2 — Value-gating (requiresPro) + FREE_BATCH_LIMIT
**Notion**: https://app.notion.com/p/385be5ec9ff6813cb870fda37a8d5166
**Effort**: S | **Priority**: High | **Dependencies**: 2.1
**Overview**: Free basic conversion + small PDF up to FREE_BATCH_LIMIT (≈5); Pro for large batch, resize-to-size, strip. Unit-tested.

---

## Phase 3: Services

### 3.1 — ConversionEngine actor (ImageIO + batch core)
**Notion**: https://app.notion.com/p/385be5ec9ff681ac8d11c7d1e7835c7f
**Effort**: M | **Priority**: High | **Dependencies**: 2.1
**Overview**: On-device HEIC/PNG/JPG/HEIC conversion via ImageIO; bounded-concurrency batch; per-item failure isolation; zero network.

### 3.2 — Resize & compress (max dimension + target size)
**Notion**: https://app.notion.com/p/385be5ec9ff681e59f81ef7c4a0de60f
**Effort**: M | **Priority**: High | **Dependencies**: 3.1
**Overview**: maxDimension downscale + resize-to-target-file-size (quality binary search), downsample-on-load.

### 3.3 — Strip EXIF/GPS metadata + test
**Notion**: https://app.notion.com/p/385be5ec9ff6812a82c8c195bffc436c
**Effort**: S | **Priority**: High | **Dependencies**: 3.1
**Overview**: Write output without GPS/EXIF when enabled; unit test asserts no GPS. Privacy-critical.

### 3.4 — Image→multi-page PDF (PDFKit)
**Notion**: https://app.notion.com/p/385be5ec9ff6817d8f92e207baeff912
**Effort**: M | **Priority**: High | **Dependencies**: 3.1
**Overview**: N images → one multi-page PDF in order; our top ASO acquisition surface.

### 3.5 — Import service (PhotosPicker + Files + iCloud)
**Notion**: https://app.notion.com/p/385be5ec9ff681aea340d5d9853553af
**Effort**: M | **Priority**: High | **Dependencies**: 2.1
**Overview**: Multi-select PhotosPicker + Files import + iCloud-optimized download (never upload) + unsupported handling.

---

## Phase 4: Shell

### 4.1 — App shell: entry + NavigationStack + Convert skeleton
**Notion**: https://app.notion.com/p/385be5ec9ff681febfdbce6e27c49ce4
**Effort**: M | **Priority**: High | **Dependencies**: 1.3, 2.1
**Overview**: App entry, NavigationStack, themed Convert scaffold + Settings entry.

---

## Phase 5: Features

### 5.1 — Convert queue UI (thumbnail grid)
**Notion**: https://app.notion.com/p/385be5ec9ff6815e8640e089df571b55
**Effort**: M | **Priority**: High | **Dependencies**: 3.5, 4.1
**Overview**: Thumbnail grid with add/remove, on-device badge, empty state.

### 5.2 — Options sheet (format, quality, resize, strip; Pro locks)
**Notion**: https://app.notion.com/p/385be5ec9ff681998d7dde1e23db8800
**Effort**: M | **Priority**: High | **Dependencies**: 5.1, 2.2
**Overview**: Target format/quality/resize/strip bound to ConversionOptions; amber Pro locks on gated controls.

### 5.3 — Batch convert + "Developing" reveal animation
**Notion**: https://app.notion.com/p/385be5ec9ff68125a2bac53f8e6b507a
**Effort**: M | **Priority**: High | **Dependencies**: 3.1, 5.1
**Overview**: Convert → engine; signature develop reveal per item; Reduced-Motion crossfade; cancel; success haptic.

### 5.4 — Results sheet (sizes, Save, Share)
**Notion**: https://app.notion.com/p/385be5ec9ff6817eb8cfce21b0797750
**Effort**: M | **Priority**: High | **Dependencies**: 5.3
**Overview**: Outputs with sizes; Save to Photos (add-only)/Files; Share batch.

### 5.5 — PDF assembly UI (To PDF, reorder)
**Notion**: https://app.notion.com/p/385be5ec9ff68120aafcd2ee3c6a84bf
**Effort**: S | **Priority**: Medium | **Dependencies**: 3.4, 5.2
**Overview**: To-PDF action + drag-to-reorder pages; small PDF free.

---

## Phase 6: Monetization

### 6.1 — RevenueCat setup + products + offline entitlement
**Notion**: https://app.notion.com/p/385be5ec9ff6810bbc23e34717d17f49
**Effort**: M | **Priority**: High | **Dependencies**: 1.2, 2.2
**Overview**: Offerings for annual $9.99 / weekly $1.99 / lifetime $19.99; purchase + restore; offline-cached entitlement.

### 6.2 — Paywall screen (honest, annual default, restore)
**Notion**: https://app.notion.com/p/385be5ec9ff6810ba320ea0f39939ce5
**Effort**: M | **Priority**: High | **Dependencies**: 6.1, 1.3
**Overview**: Warm Darkroom paywall — on-device badge, benefits, annual default, restore, no dark patterns.

### 6.3 — Wire value-gate triggers → paywall
**Notion**: https://app.notion.com/p/385be5ec9ff681769cc2cc1a62528826
**Effort**: S | **Priority**: High | **Dependencies**: 6.2, 2.2
**Overview**: Present paywall on Pro actions; resume the tapped action after purchase; emit pro_gate_hit.

---

## Phase 7: Onboarding

### 7.1 — Onboarding (3 screens) + permissions + empty state
**Notion**: https://app.notion.com/p/385be5ec9ff681aaa64fc0c379184a4f
**Effort**: M | **Priority**: Medium | **Dependencies**: 4.1, 1.3
**Overview**: ≤3 skippable screens (value → "never uploaded" → add photos); shown once; ends on empty state.

---

## Phase 8: Settings

### 8.1 — Settings (defaults, restore/manage, privacy statement)
**Notion**: https://app.notion.com/p/385be5ec9ff681ff8c39c6cc67470f89
**Effort**: M | **Priority**: Medium | **Dependencies**: 6.1, 1.3
**Overview**: Defaults via AppStorage; restore/manage subscription; literally-true privacy statement; Terms.

---

## Phase 9: Analytics

### 9.1 — TelemetryDeck events + MetricKit crash
**Notion**: https://app.notion.com/p/385be5ec9ff68173822fd6c9ec35303e
**Effort**: M | **Priority**: Medium | **Dependencies**: 1.2
**Overview**: Privacy-first analytics for the §7 events + MetricKit; never sends content/PII.

---

## Phase 10: Polish

### 10.1 — Accessibility (VoiceOver, Dynamic Type, 44pt)
**Notion**: https://app.notion.com/p/385be5ec9ff681eabe3fe60e47b18e59
**Effort**: M | **Priority**: High | **Dependencies**: 5.4, 6.2, 7.1, 8.1
**Overview**: VoiceOver labels/hints, Dynamic Type to XXL (serif), 44pt targets, AA contrast, no color-only signals.

### 10.2 — Liquid Glass + haptics + dark/light audit
**Notion**: https://app.notion.com/p/385be5ec9ff6819bbb3fcc6aa6381076
**Effort**: M | **Priority**: Medium | **Dependencies**: 5.4, 6.2
**Overview**: Adopt iOS 26 Liquid Glass tastefully; spec'd haptics; full dark/light audit.

### 10.3 — Performance & memory (concurrency, temp cleanup, 100-batch)
**Notion**: https://app.notion.com/p/385be5ec9ff681a290f5fe280cfb4262
**Effort**: M | **Priority**: High | **Dependencies**: 3.1, 5.4
**Overview**: Bounded concurrency, downsample, temp-file purge, 100-image batch crash-free, launch <1s.

### 10.4 — Zero-network-egress CI test (privacy guarantee)
**Notion**: https://app.notion.com/p/385be5ec9ff681b0b44bc2c0d04bbee1
**Effort**: S | **Priority**: High | **Dependencies**: 3.1
**Overview**: CI test asserting no network during conversion — locks the "never uploaded" promise in code.

---

## Phase 11: App Store

### 11.1 — ASC setup, metadata (Astro), screenshots, privacy label
**Notion**: https://app.notion.com/p/385be5ec9ff681428adddbcac9576155
**Effort**: M | **Priority**: High | **Dependencies**: 6.1
**Overview**: Products + Astro-driven metadata (name/subtitle/keywords) + 5 screenshots + accurate privacy label.

---

## Phase 12: Testing

### 12.1 — Unit tests (engine, gating, strip, resize)
**Notion**: https://app.notion.com/p/385be5ec9ff68157a53fd50af801200e
**Effort**: M | **Priority**: High | **Dependencies**: 3.2, 3.3, 2.2
**Overview**: Swift Testing suite covering conversion, gating boundaries, EXIF-strip, resize/target-size.

### 12.2 — TestFlight build + submission checklist
**Notion**: https://app.notion.com/p/385be5ec9ff68148be11e90513add392
**Effort**: S | **Priority**: Medium | **Dependencies**: 11.1, 12.1, 10.3
**Overview**: Signed TestFlight build (Fastlane) + subscription/privacy/4.3 submission checklist.

---

## Changelog

| Date | Changes |
|------|---------|
| 2026-06-20 | Initial Notion task breakdown from PRD v1.0 (29 tasks, 12 phases) |
