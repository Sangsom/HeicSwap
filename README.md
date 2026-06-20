# HeicSwap

HeicSwap is a privacy-first, **on-device** image converter for iOS 26 — convert HEIC/PNG/JPG, build PDFs, resize/compress, and strip metadata without anything leaving the device. Single app target, Swift Package Manager only, Swift 6 with strict concurrency enabled.

## Prerequisites

- **Xcode 26+** — Required for Swift 6 and the iOS 26 SDK
- **iOS 26** — Deployment target

## Setup

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd HeicSwap
   ```

2. Open the project in Xcode:
   ```bash
   open HeicSwap.xcodeproj
   ```

3. Select your development team in **Signing & Capabilities** for both the app and test targets.

4. Build and run (⌘R).

## Developer Setup

Before first run, configure these items:

| Item | Purpose |
|------|---------|
| **Secrets.xcconfig** | Generated at build from `.secrets` via a Run Script. Copy `.secrets.example` → `.secrets`, add `REVENUECAT_API_KEY` and `TELEMETRYDECK_APP_ID`. Never commit `.secrets`. |
| **StoreKit config** | Add a `.storekit` configuration file for local subscription testing, then enable it in Scheme → Run → Options → StoreKit Configuration. (Added in the monetization task.) |

See [HeicSwap/Documentation/Features.md](HeicSwap/Documentation/Features.md) for architecture details.

### RevenueCat Entitlement

Set the entitlement identifier in the RevenueCat Dashboard (Project → Entitlements). It must match the value used in `PurchaseService` (default: `"pro"`). Attach your products to this entitlement.

### Analytics & Privacy

HeicSwap is privacy-first: **no ad/tracking SDKs (no Firebase), and no network egress during conversion.** Analytics is abstracted behind the `AnalyticsClient` protocol so feature code never imports an SDK. The production backend is the privacy-respecting `TelemetryDeckAnalyticsClient` (no-op until `TELEMETRYDECK_APP_ID` is set); previews and tests use `StubAnalyticsClient`. The event catalog and MetricKit reporting are added in a later task (9.1). In-app purchases are likewise fronted by `PurchaseClient` (`PurchaseService`, RevenueCat-backed).

### Fastlane

Configure `fastlane/Appfile` with your `app_identifier`, `apple_id`, and `team_id`. For CI, use `FASTLANE_APPLE_ID` and `FASTLANE_TEAM_ID` environment variables.

- **Build IPA:** `fastlane build`
- **Upload to TestFlight:** `fastlane beta`
- **Screenshots:** `fastlane screenshots` (requires `fastlane snapshot init` and UI tests with `snapshot()` calls)

## Adding Dependencies

Use **Swift Package Manager** only:

1. **File → Add Package Dependencies...**
2. Enter the package URL.
3. Select the version and add to the app target.

## Project Layout

```
HeicSwap/
├── App/            # App entry, AppDelegate, AppState, MainTabView
├── Models/         # Domain models & enums
├── Services/       # PurchaseClient/PurchaseService, AnalyticsClient/TelemetryDeckAnalyticsClient
├── Features/       # Feature screens (Convert, Settings, …)
├── DesignSystem/   # Colors, typography, design tokens
├── Resources/      # Assets, LaunchScreen
├── Components/     # Reusable UI (EmptyStateView, PaywallPresenter)
├── Core/           # DI environment, utilities, persistence/repository placeholders
└── Documentation/  # Project docs
```

## Tech Stack

- **Swift 6** — strict concurrency = complete
- **SwiftUI** — primary UI framework; MVVM with `@Observable`
- **Swift Package Manager** — dependency management (RevenueCat, TelemetryDeck)
- **Swift Testing** — unit tests (`@Test`, `#expect`)
