# Codex — take over from Claude (Nov 4, 13:35)

Read `AGENTS.md` first (whole file). Vu (designer) talks Vietnamese; UI copy stays English.
You have full access to this folder. Everything below is on Vu's Mac under
`~/Desktop/iphone-18-pro-max-high-quality-3d-model/`.

## Build, run, check (do this after every change)
```
export DEVELOPER_DIR=/Users/vunguyen/Desktop/Xcode-beta.app/Contents/Developer   # Xcode 27.3 beta (don't change xcode-select)
bash _vert/co.sh          # build + install on both simulators + screenshots into _vert/simshots/
bash _vert/one.sh <screen> # build + open one screen (Pro Max) + screenshot
bash _vert/release.sh     # Release build + .app size
```
Simulators: iPhone 18 Pro `E1506FD5-5CFB-4B7A-ABD1-EF7D5558A352` (narrow — test here first), iPhone 18 Pro Max `54B67C9B-28C9-4698-98A3-968BA4AB75B6`.
Xcode 27 has no Simulator.app: the window is **Device Hub** (`Xcode-beta.app/Contents/Applications/DeviceHub.app`).
Open any screen directly: `xcrun simctl launch <udid> com.chargefuze.redesign.demo -demo <scan|walk|code|arrive|signin|checkout|charging|eject|renting|rentalsheet|return|swapwhy|swap>`; home sheet states: `-collapsed`, `-expanded`.
If Xcode shows "Cannot find X in scope" after files moved: quit and reopen the project (stale index); the CLI build is the truth.
The web prototype (reference for every screen) is `ChargeFuze-prototype/proto/index.html` (`npx serve ChargeFuze-prototype/proto`).

## Design rules Vu enforced today (keep them)
- Buttons: capsule actions **44 pt** (`Theme.buttonHeight`) drawn with `FilledCapsuleStyle` (NOT `.glassProminent`, it adds padding); round icon buttons **44 pt** with `GlassCircleStyle` (NOT `.glass` + `.circle`). Side-by-side buttons must be the same height. Titles one line (shrink to 0.8).
- Bottom cards float with the **same gap at the sides and the bottom** (`.floatingAtBottom(8)` + `.bottomCard` concentric shape); inner padding `Theme.cardInset` (16). System sheets: content hugs its height (measured with `onGeometryChange` → `.presentationDetents([.height(h)])`), no empty band at the bottom.
- Colour: blue only for the ONE main action per screen (+ the "Faster" text, the route, the locate arrow). Soft fills are neutral grey (`Theme.brandSoft` is now grey). Glass icon buttons use ink/white icons. "Need more time?" icon black, "Find a return station" black, Apple Pay black.
- Type: nothing below 11 pt; secondary text ≥ 13 (footnote); body/list 15–17. Sheet titles `.headline`, not big banners.
- Icons: **SF Symbols** everywhere (`LucideIcon` / `Image(lucide:)` now render SF Symbols, semibold). The Lucide asset set was removed.
- Lists like the web: rows flat on the sheet, no per-row frames; peek row = light white card; picked row in the full list = white card; name ↔ price on one baseline, name truncates with "…".
- Walking: route cut at the point nearest the kiosk + dashed leg INTO the kiosk; the dot walks all the way in; arrival only at the kiosk; "See the spot · 360°" (Apple Look Around) only on the arrival card. Maps pinch/zoom + `MapZoomControl`; dragging pauses the follow camera, "Re-center" brings it back.

## Open items (in priority order)
1. **Walk through every flow by hand in Device Hub** (tap, not only screenshots): home → Go → walk → arrive → Scan → pay → charging → renting bar → details (drag up) → Find a return station → I'm here → receipt; Phone about to die → sign in → code → pay → code box; Charger not working → reasons → swap. Fix anything that looks off vs the web prototype.
2. Spacing/size sweep of the screens not reviewed today: AccountView, RentalsView, HelpView, ReturnFlowView, StationSheet, DirectionsView, QuickRentView, FixGuide, receipt sheet, KeepLongerSheet. Apply the rules above (44 pt buttons, styles, neutral fills, type sizes).
3. Rental details sheet: confirm the native drag between the compact and expanded detents feels smooth on device; the top-right chevron also toggles it.
4. Web prototype parity for today's app-only changes (exact kiosk spot + dashed leg + walk-in, 360° only on arrival, neutral code box, flat list rows, 44 pt buttons) — the web is the spec Vu shows the client.
5. API: fill the paths in `Core/Services/Services.swift` `Live*Service` with the backend team; set `API_BASE_URL` in Info.plist per configuration; wire `KioskEventService` (WebSocket/SSE) into the arrival / return / swap screens (today they use timers).
6. Release: archive (strip + bitcode-free), check download size, add the privacy manifest + location/notification usage strings review, remove the `-demo` launch handling behind `#if DEBUG`.
7. Empty `_to_delete/` at the project root (deletes are blocked for Claude).

## Sync note
Claude edited a mirror in its sandbox and pushed tarballs into `_sync/` (`_vert/sync.sh <tgz>` overwrites files in place). You edit the Mac files directly — no sync needed.

## Codex follow-up — Nov 4

- Device Hub, iPhone 18 Pro (iOS 27.3): tapped through walk → arrival → scan → checkout → charging → rental → guided return → receipt, walk → demo SMS → pay ahead → unlock code, and swap reasons → walk → Swapped. Debug built and installed on Pro and Pro Max.
- Updated the secondary screens to the current 44 pt controls and neutral styles. Keep it longer and receipt measure their content for the sheet height. The rental chevron switches both detents. The native drag gesture still needs a physical-device check because the injected simulator drag did not change detent.
- The local web prototype now retains exact kiosk coordinates and draws a dashed leg from the street to the venue, shows 360° only after arrival, and uses neutral code/row styling and 44 px CTAs. Verified in the browser, including paying after arrival.
- Live API and kiosk events still need backend documentation and staging/production URLs. API_BASE_URL is a per-configuration setting and is empty in the demo build. Checkout advertises the first 3 minutes free but the demo receipt charged $1 for a short rental. Confirm the grace-period billing rule with the backend before production.
- Release archive succeeded with signing disabled, stripped binary, dSYMs, no bitcode, and no -demo entry point. Added the UserDefaults required-reason manifest and revised the location prompt. iOS controls the notification prompt copy. The archived app occupies 4.4 MiB on disk, which is not the App Store download size. Distribution signing, server data disclosures and the live integrations still need validation.
- Finder confirmed that _to_delete is empty. The old Swift layout is recoverable in Trash.

## Web workflow parity follow-up — November 4

- Latest owner instruction takes priority over earlier layout notes. Follow the existing web workflow. The intermediate Find the kiosk / I'm at the kiosk step has been removed.
- WalkView preserves the MapKit street route and uses the web's dashed demo approach to the kiosk pin. The demo automatically opens arrival, guided return, or swap once it reaches that pin. Look Around remains gated to kiosk proximity and pauses the demo while open.
- Guided return has a close button and two progress segments like the web. Closing the cover cancels its task and returns to the map. It hands off through onDismiss before opening the receipt or unconfirmed-return view.
- Restored the web route reveal, pin-to-row flash and locate pulse. The return-unconfirmed demo switch reaches the existing verification screen through both the direct return and walking routes.
- Swap now records the replacement slot and the web's zero-value refund activity when the demo replacement is taken.
- Simulator verification uses the existing Debug screen launcher. Added return-walk, return-walk-unconfirmed and swap-walk launch cases for the specific transition regression.
- Verified iPhone 18 Pro and Pro Max on iOS 27.3 with screenshots of completed return, completed swap, the return-unconfirmed screen and pay-ahead arrival continuing to charging. iOS 26 and physical-device sheet gestures remain unverified.
- Browser control is disabled in the current Work settings. This pass compared the local web source. Native Device Hub control also failed to attach, so this pass used simulator launch arguments and screenshots.
- Backend URLs, live SMS/payment/kiosk events and the first-three-minutes billing discrepancy still require engineering input. The source handoff and unsigned Release archive are rebuilt after this pass.

## Claude parity additions (Nov 4, late)
- `DesignSystem/Components.swift`: new `TopBanner` (iOS-style glass banner, slides from top, tap action).
- `RentalMapView`: "Not charging?" banner (from `AppModel.notChargingBanner`, auto-hides 10 s, tap → swap reasons) and "Next $X starts soon" banner (once per billing block when < 5 min left, hides 7 s, tap → return flow). Matches the web toasts.
- `AppModel.watchCharging` now raises the banner instead of opening the reasons sheet directly.
- New demo args: `-demo notcharging`, `-demo nextcharge`.
- Still web-only (consider next): toasts "Charger released · pull it out", "Receipt sent", "Slot held for 15 min", "Location is off".

- Unlock-code flip now starts from an explicit keyframe trigger after the view mounts. Matches the web's 200 ms per digit and 50 ms stagger, plays once per appearance/code, and respects Reduce Motion. Verified from simulator video frame by frame.

## Engineering cleanup — Claude, Nov 4 evening (keep when you edit)
- New engineer docs: `README.md` (build, layout, design rules, `-demo` list) and `INTEGRATION.md` (endpoint table, kiosk events, TODOs). Old `HANDOFF.md` retired (it described the pre-restructure layout).
- Service layer: added `ReturnService`, `AccountService`, `SupportService`, `LiveKioskEventService` (SSE via `APIClient.lines`), `SessionStore` (Keychain token). `RentalTicket.slot`.
- `AppModel` now calls services for rent (`pay()` → `rentals.start` + live `waitForKiosk`), unlock code, keep longer (`keepLonger(hours:)`), issue report (`reportChargerIssue`), hold slot, return claim, pass rental, promo (`applyPromo` is async), pass, tickets, sign-in (`sendSignInCode` / `verifySignIn`). Demo behaviour unchanged (mock answers at once; timers only when `isDemo`).
- Demo-only code moved to `Core/Mock/AppModel+Demo.swift` (`runDemo`, `redeemDemoUnlockCode`, `completeDemoSwap`, `fastForward`, `replayOnboarding`). Account › Demo section shows only when `isDemo`.
- `Lucide.swift` → `DesignSystem/Icons.swift`: `LucideIcon` → `AppIcon`, `Label(_:lucide:)` → `Label(_:symbol:)`, `Image(lucide:)` → `Image(systemName:)`.
- `RentPlan`, `HeldSlot` moved to `Models.swift`; demo user name/phone moved to `MockData`.
- Verified: Debug build succeeded; code / renting / charging / eject / return / signin screens checked on iPhone 18 Pro Max.

## Checkout button follow-up — Nov 4, evening
- Checkout keeps its PassKit control mounted during pricing and disables the footer's inherited step animation, so it does not wait to create the Apple Pay control on summary entry.
- The outer black capsule retains the shared 46 pt tap target; native Apple Pay artwork uses a compact 36 pt height, reducing the oversized checkout title without recreating the logo. Payment callbacks and the existing flow are unchanged.
- Debug built and installed on Pro and Pro Max; unsigned Release archive succeeded. Resumed Device Hub verification after unlock: recorded pricing-to-summary transitions for rent and pay-ahead; the black button is present with summary content, compact title checked, pricing reopened and Apple Pay → Visa → Apple Pay verified. Both demo payment callbacks continued to charging. UI interaction was verified on Pro (iOS 27.3); Pro Max installed, iOS 26 remains untested.
