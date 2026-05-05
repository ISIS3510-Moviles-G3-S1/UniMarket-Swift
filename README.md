# UniMarket

A second-hand clothing marketplace for students at Universidad de Los Andes. Buy and sell pre-loved pieces within your campus community.

Built with SwiftUI + Firebase. A companion Flutter app exists in a separate repository.

---

## Getting Started

### Prerequisites

- Xcode 15+
- An active internet connection (Firebase dependencies are fetched via SPM on first build)
- Access to the team's Firebase project credentials

### Configuration

API keys are not committed to the repo. Before building:

1. Copy the template config file:
   ```
   cp Config.xcconfig.template UniMarket-Swift/UniMarket-Swift/Config.xcconfig
   ```
2. Fill in the values (get them from the team group chat)
3. Build and run — never drag `Config.xcconfig` into Xcode's file navigator

### Build & Run

Open `UniMarket-Swift/UniMarket-Swift.xcodeproj` in Xcode, select the **iPhone 16** simulator, and hit Run.

```bash
# CLI build
xcodebuild -project UniMarket-Swift/UniMarket-Swift.xcodeproj \
           -scheme UniMarket-Swift \
           -destination 'platform=iOS Simulator,name=iPhone 16' \
           build
```

---

## Architecture

| Layer | Role |
|---|---|
| **Stores** (`SessionManager`, `ProductStore`, `ChatStore`) | Global singletons injected as `@EnvironmentObject`. Own all Firestore listeners and live data. |
| **ViewModels** | `@MainActor ObservableObject`s, one per screen. Receive data from views/stores, never access stores directly. |
| **Views / Components** | Pure SwiftUI. Read from ViewModels and environment. |
| **Services** | Stateless singletons for Firestore CRUD, image upload, AI tagging, and analytics. |

Navigation is driven entirely by `SessionManager.isLoggedIn` from `RootView`. Auth is restricted to `@uniandes.edu.co` emails with mandatory email verification.

---

## Key Features

- **Browse & Search** — filter by price, condition, rating, tags, and favourites; debounced live search
- **AI Stylist** — chat with an LLM-powered style assistant; conversations persisted to disk per user
- **Recommendations** — personalised product scoring with parallel async computation
- **Real-time Chat** — Firestore-backed buyer/seller messaging with unread counts
- **Activity** — saved items (likes) and your own listings in one place
- **Seller Profile** — XP system, sustainability impact, eco messages, and performance metrics
- **Offline Support** — pending uploads, messages, and favourite changes queue locally and sync when connectivity returns

---

## Analytics

All events are strongly typed as cases of `AnalyticsEvent` and tracked through `AnalyticsService`. To add a new event, add a case to `AnalyticsEvent` and call `AnalyticsService.shared.track(.)`.

---

## Dependencies

Managed via Xcode's built-in Swift Package Manager — no `Package.swift` needed.

- Firebase (Auth, Firestore, Analytics, Storage, AI)
- Kingfisher (image loading & caching)
- OpenRouter (AI Stylist LLM backend)
