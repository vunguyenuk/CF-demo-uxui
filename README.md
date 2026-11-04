# chargeFUZE iOS (redesign)

SwiftUI app for renting a phone charger from a chargeFUZE kiosk: find the closest kiosk, walk there, rent, return, swap.
It runs today on **mock data** (a full clickable demo). The backend plugs in behind one service layer, and the screens don't need to change.

- **Design reference (web prototype):** https://claude.ai/artifact/B2gzEszQE9BG3ChhKEYoab. Every screen and motion in the app follows it.
- **Backend integration:** see [`INTEGRATION.md`](INTEGRATION.md).
- **Notes from the design and AI passes:** [`docs/design-notes/AGENTS.md`](docs/design-notes/AGENTS.md) and [`docs/design-notes/CODEX_TASKS.md`](docs/design-notes/CODEX_TASKS.md) (design rules, history, open items).
- **Web prototype source:** [`web-prototype/`](web-prototype/) — run `npx serve web-prototype` and open the printed URL.

## Requirements
- Xcode 26 or newer (tested with Xcode 27.3 beta, iOS 27.3 simulator). Deployment target is **iOS 26.0**.
- Swift 6 language mode, SwiftUI only. No third-party packages.
- Two targets: `ChargeFuze` (app) and `ChargeFuzeWidgets` (Live Activities).

## Build and run
1. Open `ChargeFuze.xcodeproj`.
2. Pick your Team under Signing & Capabilities for **both** targets.
3. Run on an iPhone or a simulator (iPhone 18 Pro is the narrowest layout we check).

From the command line:
```sh
xcodebuild -project ChargeFuze.xcodeproj -scheme ChargeFuze -configuration Debug \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

### Jump to any screen (Debug only)
```sh
xcrun simctl launch <udid> com.chargefuze.redesign.demo -demo <screen>
```
| `<screen>` | What it opens |
| --- | --- |
| `scan`, `checkout`, `signin` | QR scanner, pay sheet, phone sign-in |
| `walk`, `arrive`, `code` | walking route, arrival at the kiosk, pay-ahead unlock code |
| `charging`, `eject` | charger released, kiosk didn't release one |
| `renting`, `rentalsheet`, `nextcharge` | rental map, rental details, "next $ starts soon" banner |
| `return`, `return-unconfirmed`, `return-walk`, `return-walk-unconfirmed` | the return flows |
| `swapwhy`, `swap`, `swap-walk`, `notcharging` | the swap flows |

Add `-collapsed` or `-expanded` to set the home sheet height. The code for this is in `Core/Mock/AppModel+Demo.swift`, and it is compiled out of Release builds.

## Project layout
```
ChargeFuze/
  App/                ChargeFuzeApp (entry point, deep links, Live Activity hooks), RootView
  Core/
    Models/           Station, Rate, Rental, RentalRecord, PaymentMethod, ChargeLine, SupportTicket, RentPlan, HeldSlot…
                      ChargeAlertAttributes (shared with the widget target)
    State/            AppModel: the one @Observable store: app state, navigation and flow logic
    Services/         Services.swift: backend protocols + Mock* + Live* implementations
    Networking/       APIClient (typed async/await HTTP + SSE), SessionStore (Keychain token)
    Mock/             MockData (demo kiosks around Pershing Square, LA), AppModel+Demo (QA launch arguments)
  DesignSystem/       Theme (colours, sizes, money/time formatting), Components (buttons, cards, banners…),
                      Icons (AppIcon / Label(_:symbol:) = SF Symbols)
  Features/
    Onboarding/       splash, location step, phone sign-in sheet
    Home/             HomeContainer, NearbyHomeView (idle map + kiosk list), RentalMapView (while renting),
                      StationSheet, Keep-longer + receipt sheets
    Walk/             WalkView (MapKit walking route, walk into the kiosk, arrival, Look Around 360°), DirectionsView
    Rent/             RentFlowView (scan → charging), CheckoutFlow (pay sheet), QuickRentView (low battery pay-ahead),
                      ActiveRentalSheet, FixGuide
    Return/           ReturnFlowView (find + hold slot → verify → receipt; proof-of-return when the kiosk can't confirm)
    Swap/             SwapReasonSheet ("what's wrong?"), SwapView
    Account/, Help/   account, payment, passes, rentals and money activity; help assistant
  Resources/          HEVC clips (Blender renders), PrivacyInfo.xcprivacy
ChargeFuzeWidgets/    Live Activities: low battery, running rental
```

## How it fits together
- **Views never call the network.** They read and mutate `AppModel` (`@Environment(AppModel.self)`).
- **`AppModel` calls `services`**, which is a `Services` value with one protocol per backend area: stations, auth, rentals, kiosk events, returns, account and support.
- `Services.current` is **live** when `API_BASE_URL` is set for the build configuration. Otherwise it uses the **mock** services, and `model.isDemo == true`.
- Demo-only behaviour (timers that stand in for kiosk events, the Account › Demo switches, `-demo` launch arguments) is gated by `isDemo` or `#if DEBUG`. Live builds wait for real kiosk events instead (`AppModel.waitForKiosk`).
- Each piece of state and logic has a single source: rent (`pay()`), return (`returnHere`, `completeReturn`), swap, sign-in (`sendSignInCode` / `verifySignIn`).

## Design rules (please keep)
- Capsule buttons are **44 pt** (`Theme.buttonHeight`, `FilledCapsuleStyle`). Round icon buttons are 44 pt with `GlassCircleStyle`. Buttons that sit side by side have the same height.
- Bottom cards float with the same gap at the sides and at the bottom: `.floatingAtBottom(8)` + `.bottomCard`. System sheets measure their content: `onGeometryChange` → `.presentationDetents([.height(h)])`.
- Blue is for the **one** main action per screen, the route and the locate arrow only. Everything else is neutral grey or ink.
- Type is never below 11 pt. Secondary text is ≥ 13 pt. List and body text is 15–17 pt.
- Icons are **SF Symbols** (`AppIcon`, `Label(_:symbol:)`).
- Walking: the route goes into the exact kiosk spot. "See the spot · 360°" (Apple Look Around) shows only once the user has arrived.
