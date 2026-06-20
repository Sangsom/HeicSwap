# App Profile: HeicSwap

> **Last updated**: 2026-06-20
> **Bundle ID**: com.domanovs.rinalds.ios.HeicSwap
> **Minimum iOS**: 26.0
> **Status**: Planning (project scaffolded — tasks 1.1–1.2 complete; features not yet built)

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
| _(none yet — scaffold only)_ | Project foundation: Swift 6 / iOS 26 / MVVM structure | Simple |

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
Currently a placeholder `MainTabView` (Home / Settings) from the template. The real shell — a `NavigationStack` Convert flow with a Settings entry — is built in task 4.1.

### Source Layout
```
HeicSwap/
├── App/            # HeicSwapApp, AppDelegate (minimal), AppState, MainTabView
├── Models/         # Domain models & enums (task 2.1)
├── Services/       # PurchaseService, AnalyticsService
├── Features/       # Home, Settings (placeholders)
├── DesignSystem/   # Colors, Typography (Warm Darkroom theme in task 1.3)
├── Resources/      # Assets, LaunchScreen
├── Components/     # EmptyStateView, PaywallPresenter
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
| Placeholder shell | Low | `MainTabView` + Home "Hello, world!" are template placeholders, replaced in task 4.1 |
| `DesignSystem` holds template tokens | Low | `Theme`/`Colors`/`Typography` are template defaults; reworked into Warm Darkroom in task 1.3 |
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
