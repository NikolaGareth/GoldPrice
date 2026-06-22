# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run Commands

```bash
# Debug run (macOS)
swift build && .build/debug/GoldPrice

# Release build only
swift build -c release

# Package as .dmg (macOS)
bash scripts/build.sh

# iOS IPA build
bash scripts/build_ios_ipa.sh

# Watch mode (rebuild on change)
bash scripts/watch.sh
```

The iOS Xcode project lives at `ios/GoldPriceiOS.xcodeproj`. Open it in Xcode to build and run on a simulator or device. The Swift Package (`Package.swift`) only targets macOS and produces the status bar executable.

## Architecture

This is a **dual-platform** Swift app sharing most business logic between a macOS menu bar app and an iOS app.

### Shared layer (used by both platforms)

- **`Sources/Models/PriceModels.swift`** — all data models: `GoldPriceSource` enum (4 sources), `PriceInfo`, `AppSettings`, position/transaction models (`PositionInfo`, `PositionTransaction`, `PositionPerformance`), and all alert types (`PriceAlert`, `PercentageAlert`, `ProfitAlert`, `ExtremePriceAlertConfig`). `PositionLedger` is a pure static type that computes P&L from a transaction list.
- **`Sources/Services/GoldPriceService.swift`** — `ObservableObject` that fetches all 4 sources concurrently via `DispatchGroup`, drives a repeating timer, and publishes `allSourcePrices: [GoldPriceSource: PriceInfo]`. Domestic sources (JD Zheshang/Minsheng) call `OfficialIntradayChartService` to enrich day-high/low. International sources (Sina Finance) require GB18030 decoding.
- **`Sources/Services/OfficialIntradayChartService.swift`** — fetches the official intraday series for domestic sources; has a 45s cache and request coalescing.
- **`Sources/Services/PriceHistoryManager.swift`** — singleton (`shared`). Owns all file-based persistence under `~/Library/Application Support/GoldPrice/`: price history, position, positionTransactions, settings, and four alert types. Uses a serial `DispatchQueue` for history reads/writes.
- **`Sources/Shared/AppTheme.swift`** — shared `Color` extensions (`goldGreen`, `appCardBackground`, etc.) used across both platforms.
- **`Sources/Shared/PriceChartPanel.swift`** — cross-platform SwiftUI chart panel using the `Charts` framework.
- **`Sources/Shared/GoldPriceLiveActivityAttributes.swift`** — Live Activity / Dynamic Island attributes for iOS.

### macOS-only layer

- **`Sources/App/GoldPriceApp.swift`** — `@main` entry, `AppDelegate` handles notification permissions and creates `StatusBarController`.
- **`Sources/Controllers/StatusBarController.swift`** — owns the `NSStatusItem`, builds and manages the `NSMenu`, triggers alert evaluation on every price update, fires `UNUserNotificationCenter` notifications, and hosts SwiftUI views via `NSHostingView`.
- **`Sources/Views/`** — all macOS menu item views (`PriceMenuItemView`, `ChartMenuItemView`, `PositionMenuItemView`, `GoldCircleDetailView`, `MiniChartView`) plus `StatusBarPopupView` (floating panel).

### iOS-only layer

- **`Sources/Mobile/GoldPriceMobileApp.swift`** — `@main` iOS entry (guarded by `#if os(iOS)`); 4-tab navigation: 首页 / 行情 / 交易 / 设置. All tab views are defined in this single file.
- **`Sources/Mobile/GoldPriceMobileViewModel.swift`** — `ObservableObject` bridging `GoldPriceService` and `PriceHistoryManager` for SwiftUI bindings on iOS.
- **`ios/GoldPriceLiveActivity/`** — iOS widget extension for Dynamic Island / Live Activity.

### Data flow

```
GoldPriceService (fetches every N seconds)
    → allSourcePrices published
    → PriceHistoryManager.recordPrice/recordPrices (persists history)
    → StatusBarController subscribes (macOS) / GoldPriceMobileViewModel subscribes (iOS)
        → alert evaluation → UNUserNotificationCenter
        → UI update
```

### Persistence files

All under `~/Library/Application Support/GoldPrice/`:
- `priceHistory.json` — today's price records per source key; auto-cleared at midnight
- `position.json` — cached `PositionInfo` (derived from transactions)
- `positionTransactions.json` — canonical transaction ledger; `PositionInfo` is always recomputed from this
- `settings.json` — `AppSettings`
- `alerts.json`, `percentageAlerts.json`, `profitAlerts.json`, `extremePriceAlertConfigs.json`

### iOS setup notes

See `docs/IOS_APP_SETUP.md` for which source files to include/exclude when building the Xcode iOS target. The macOS-specific files (`Sources/App`, `Sources/Controllers`, `Sources/Views/MenuItems/`, `Sources/Services/GoldCircleService.swift`) must **not** be added to the iOS target.
