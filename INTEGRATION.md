# Backend integration guide

Everything the app needs from the server goes through `Core/Services/Services.swift`. Each area is a protocol with a `Mock*` implementation (the demo) and a `Live*` implementation (HTTP via `APIClient`).
The **paths and JSON below are proposals**. Change them in the `Live*` types to match the real API. No view needs to change.

## 1. Turn the live API on
1. Set the build setting **`API_BASE_URL`** per configuration in the `ChargeFuze` target (it is empty today), e.g. `https://api-staging.chargefuze.com/`. `Info.plist` reads it as `$(API_BASE_URL)`.
2. Only `https` URLs are accepted. When the value is empty, the app runs on the mock services (`AppModel.isDemo == true`).
3. JSON is `snake_case` on the wire and dates are ISO 8601 (`APIClient.encoder` / `decoder`). Errors are `{ "message": "…" }` with a non-2xx status, and they surface as `APIError`.
4. Auth: `Authorization: Bearer <token>`. The token comes from `SessionStore` (Keychain) and is saved after `AuthService.verify`.

## 2. Endpoints the app calls
| Area / protocol | Method | Proposed path | Request → response | Called from (AppModel) |
| --- | --- | --- | --- | --- |
| Stations `StationService.nearby` | GET | `v1/stations/nearby?lat&lng&radius` | → `[StationDTO]` (id, venue, spot, floor, indoor, lat, lng, chargers, empty_slots, hours, online, block_minutes, price_per_block, daily_max) | `refreshNearby()` at launch |
| Auth `sendCode` | POST | `v1/auth/code` | `{phone}` → 204 | `sendSignInCode(to:)` |
| Auth `verify` | POST | `v1/auth/verify` | `{phone, code}` → `{token}` | `verifySignIn(phone:code:)` |
| Rent `start` | POST | `v1/rentals` | `{station_id, plan, payment_id, promo}` → `{rental_id, started_at, slot?}` | `pay()` |
| Rent `buyUnlockCode` | POST | `v1/unlock-codes` | same body → `{code}` (4 digits, valid 15 min) | `buyUnlockCode(at:)` |
| Rent `extend` | POST | `v1/rentals/{id}/extend` | `{hours}` → 204 | `keepLonger(hours:)` |
| Rent `reportIssue` | POST | `v1/rentals/{id}/issues` | `{reason}` → 204 | `reportChargerIssue(_:)` (swap sheet) |
| Kiosk events | GET (SSE) | `v1/rentals/{id}/events` | stream of `data: <event>` | `waitForKiosk(rentalID:until:timeout:)` |
| Return `holdSlot` | POST | `v1/slot-holds` | `{station_id}` → `{slot, until}` | `holdSlot(at:)` |
| Return `claimReturn` | POST | `v1/rentals/{id}/return-claims` | `{station_id, slot, evidence[], photo?}` → `{id}` | `submitReturnClaim(…)` |
| Return `passRental` | POST | `v1/rentals/{id}/pass` | `{recipient}` → 204 | `passRental(to:)` |
| Account `paymentMethods` / `history` / `ledger` | GET | *(add DTOs, see TODO in `LiveAccountService`)* | → lists | `refreshAccount()` after sign-in |
| Account `redeemPromo` | POST | `v1/promos/redeem` | `{code}` → `{credit}` | `applyPromo(_:)` |
| Account `buyPass` | POST | `v1/passes` | `{station_id}` → 204 | `buyFestivalPass(at:)` |
| Support `openTicket` | POST | `v1/tickets` | `{issue, rental_id, note, evidence[]}` → `{id}` | `openTicket(…)` (Help) |

`plan` is one of `payAsYouGo`, `hourly`, `dayPass`. `issue` is one of `returnedStillCharged`, `noEject`, `notCharging`, `unexpectedCharge`, `other`.

## 3. Kiosk events (the app follows the kiosk and never asks a dying phone to confirm)
`KioskEvent`: `code_used`, `charger_released`, `charger_taken`, `charger_inserted`, `charger_locked`, `release_failed`, `faulty_seated`, `new_released`.

| Flow | Live behaviour (already wired) | Demo stand-in |
| --- | --- | --- |
| Rent (`pay()`) | waits up to 30 s for `charger_released` / `charger_taken` → charging. `release_failed` or no event → "No charger came out · not charged". | 4.2 s timer + Account › Demo switches |
| Return (`returnHere`) | waits up to 60 s for `charger_locked` → receipt. No event → proof-of-return screen. | 2.4 s timer |
| Swap (`SwapView`) | **TODO**: drive the steps with `charger_inserted` → `faulty_seated` → `new_released` → `charger_taken`. | timers in `SwapView.run()` |
| Pay-ahead code (`WalkView` / `QuickRentView`) | **TODO**: `code_used` → start the rental (today the demo redeems after a timer). | `redeemDemoUnlockCode` |
| Guided return (`ReturnFlowView`) | **TODO**: replace the step timers with `charger_inserted` / `charger_locked`. | timers |

## 4. Still to build (needs product or backend input)
- **Payments**: Apple Pay (`PKPaymentAuthorizationController`) and card entry through the payment provider's SDK. The app only sends `payment_id`. Checkout shows the promo field locally; pass `promo` to `start`.
- **Billing rule**: checkout says "first 3 minutes free", but the demo receipt charges the first block. Confirm the grace period and make `Rate.cost(for:)` match the server. The server's total is the truth on the receipt.
- **Receipts and history**: `RentalRecord` and `ChargeLine` are app models. Add DTOs in `LiveAccountService` (like `StationDTO`) once the JSON is fixed.
- **Ticket ids**: claims and tickets show a local id at once. Swap in the server id when it answers (`TODO(backend)` in `AppModel`).
- **Live Activities**: started locally today (`ChargeAlertAttributes.swift`). For updates while the app is closed, request `pushType: .token` and send the token to the backend.
- **Push notifications**: block reminders are scheduled locally (`scheduleReminders()`). The server may take these over.
- **Location**: the demo pins the user at Pershing Square (`MockData.userLocation`). Feed `AppModel.userLocation` from `CLLocationUpdate.liveUpdates()` in live builds.
- **Deep links**: `chargefuze://directions/<station>`, `chargefuze://quickrent/<station>`, `chargefuze://return` (`AppModel.handle(url:)`). Add Universal Links and an App Clip for kiosk QR codes if wanted.

## 5. Checklist for a release build
- [ ] `API_BASE_URL` set for Release, and staging for Debug if wanted
- [ ] Signing teams on both targets, App Group if the widget needs shared data
- [ ] Privacy manifest `Resources/PrivacyInfo.xcprivacy` reviewed against the data the API collects
- [ ] Location / camera usage strings reviewed (target build settings `INFOPLIST_KEY_*`)
- [x] `-demo` launch handling is `#if DEBUG`, and the Account › Demo section only shows when `isDemo`.
