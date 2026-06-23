# Features

## Setup

1. **Clone and open** — Clone the repo, open `HeicSwap.xcodeproj` in Xcode.
2. **Secrets** — Copy `.secrets.example` to `.secrets`, add `REVENUECAT_API_KEY`. The build phase generates `Secrets.xcconfig` from `.secrets`.
3. **StoreKit config** — Add a `.storekit` file for local subscription testing and enable it in Scheme → Run → Options → StoreKit Configuration. (Added in the monetization task.)
4. **Signing** — Select your development team in Signing & Capabilities for app and test targets.

## RevenueCat

- **PurchaseService** — Wraps RevenueCat for subscriptions. Configured in `AppState.loadInitialState()`.
- **Entitlement** — Set the entitlement ID in the RevenueCat Dashboard; must match `PurchaseService` (default: `"pro"`).
- **PaywallSheet** (`Features/Paywall/`) — Custom Warm Darkroom paywall: on-device badge, honest benefits, annual default, weekly/lifetime, Restore + Terms/Privacy. Prices from `EntitlementStore`; no RevenueCat-hosted UI.

## Analytics & Privacy

- **Privacy-first** — No third-party tracking SDKs; no network egress during conversion.
- **AnalyticsService** — Protocol-based abstraction with type-safe events via the `AnalyticsEvent` enum. Currently backed by a no-op `StubAnalyticsService`; a TelemetryDeck-backed implementation and MetricKit crash reporting are added in a later task.

## Architecture

- **MVVM** — ViewModels own logic; views are thin renderers.
- **Services** — Injected via `@Environment` (`analyticsService`, `purchaseService`). `AppState` holds shared state and lifecycle.
- **App flow** — `HeicSwapApp` → `AppDelegate` (minimal launch hook) → `AppState` (RevenueCat config, foreground refresh) → `MainTabView` → feature screens.
- **Folder structure** — App/, Models/, Services/, Features/, DesignSystem/, Resources/, Components/, Core/, Documentation/.

## Project Structure

```
HeicSwap/
├── App/                    # App entry, AppDelegate, AppState, MainTabView
├── Models/                 # Domain models & enums
├── Components/             # Reusable UI (EmptyStateView, PaywallPresenter)
├── Core/
│   ├── Persistence/       # Data models placeholder
│   ├── Repositories/      # Data access placeholder
│   ├── UI/                # ServiceEnvironment, utilities
│   └── Utilities/         # SecretsProvider, extensions
├── Features/
│   ├── Home/
│   └── Settings/
├── Services/               # PurchaseService, AnalyticsService
├── Resources/              # Assets, LaunchScreen
├── DesignSystem/           # Colors, Typography, design tokens
└── Documentation/          # This file
```
