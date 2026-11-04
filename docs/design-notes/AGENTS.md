# ChargeFuze iOS redesign — handoff for Codex

> **Start here: `CODEX_TASKS.md`** (build/run commands, today's design rules, open items in priority order). This file is the full history.

You are picking up a design + prototype + SwiftUI project from Claude. Read this whole file before you change anything.
The owner is **Vu** (designer). He writes in Vietnamese; reply to him in Vietnamese. UI copy stays in English (US market).

---

## 1. What we are building (the brief from Vu's boss)

**Goal: rent a charger as fast as possible.** The user's phone is dying, so every extra screen is a cost.

Flow, in order:
1. 2D logo splash (no 3D, no video).
2. Sign in: phone number first (formatted US +1 field, any number works in the demo, OTP = `1234`) or Google.
3. iOS location permission sheet.
4. **Home = map + nearest kiosks (5–10)**. Pins are the real 3D Blender kiosk renders (standing, with a count badge). Uber-like list under the map with a **"Faster"** tag on the quickest one, price on the right, one big button "Go to <venue> · N min" + a QR scan square button.
5. Walk: accurate 2D route on the map (must follow streets), zoomable. A card shows ETA + progress.
6. While walking, **"Phone about to die?"** → pay now (Apple Pay / card, pickable inline) → a 4‑digit unlock code the user remembers.
7. Arrival: "You've arrived" sheet with the code; **double-tap the kiosk screen to type the code**, or scan. There is **no "I typed it" button** (the phone may be dead) — the kiosk reports the event and the app follows.
8. Take / insert screens appear **only when something goes wrong** (kiosk didn't release, charger not pulled out, return not confirmed).
9. Return: same nearest-kiosks layout ("Return to any kiosk", live time·cost pill), any empty slot works. **"Need more time? Keep it longer"** = hold the *battery* longer (no late fee until X), NOT reserve a slot.
10. Arrive at return kiosk → a real "push it in until it clicks" step (clip + 2 steps + "Waiting for the kiosk") → "Locked in · slot N" → receipt with confetti.
11. Swap a faulty charger (from the rental sheet "Charger not working?").

## 2. Where things are

All paths are on Vu's Mac under `~/Desktop/iphone-18-pro-max-high-quality-3d-model/`.

| What | Path |
|---|---|
| **Web prototype** (single file, vanilla JS) | `ChargeFuze-prototype/proto/index.html` + `proto/media/` |
| Published prototype (shareable link, owned by Claude's artifact) | https://claude.ai/artifact/B2gzEszQE9BG3ChhKEYoab — you cannot publish there; serve the local copy with `npx serve ChargeFuze-prototype/proto` |
| **SwiftUI app** (iOS 26; builds with Xcode 27 beta on Vu's Mac) | `ChargeFuzeApp/` (`ChargeFuze.xcodeproj`), engineer docs in `ChargeFuzeApp/README.md` + `ChargeFuzeApp/INTEGRATION.md` |
| Zips sent to the engineer | `ChargeFuze-iOS-handoff.zip` (rebuild it after Swift changes) |
| Blender scene used for renders (a COPY; never save over Vu's own .blend) | `_vert/kiosk_vert.blend` |
| Shot setup script (applied on top of the .blend before every render) | `_vert/setup_back.py` (previous versions: `setup_back_v25.py`, `setup_back_v26.py`) |
| Kiosk icon renders | `_vert/icons/` (`k4_standard.png` = standard kiosk; `k3_mini/tower/wide.png` = other models) |
| Rendered frame sequences / encoded clips | `_vert/seqNN/`, `_vert/chargingNN.mp4` (latest: `seq35` → `charging36.mp4`) |
| Reference photos of the real power bank | 12 HEIC photos + `IMG_0124.HEIC` (back side, plugs hidden) + video `IMG_0109.MOV` (Vu sent them in chat; ask him if you need them again) |

### Prototype code layout (`index.html`)
The file grew by **layered patches**: original app at the top, then each round appends an IIFE/CSS block **just before** the line
`window.home2=home2;window.walk2=walk2;window.arrived=arrived;window.locPrompt=locPrompt;`
Later blocks override earlier functions (`home2`, `walk2`, `arrived`, `codePay`, `codeCard`, `insertWait`, `receipt2`, `return2`, `swapFlow`, `route`, `kimg`, `takeStep`, `chargingStep` …). When you change behaviour, **append a new block** in the same style (or edit the latest override) — do not edit the old original function and expect it to win.

Key pieces (search by name):
- `splash`, `signIn`, `otp4`, `locPrompt` — first run.
- `mapLayer`, `streets()`, `bindZoom`, `f2focus` — the stylised 2D map (streets are an SVG grid rotated −28°, horizontal every 80, vertical every 90 in grid units).
- `streetRoute(s)` (ROUND 3 block) — **routes snap to that grid**: me + every kiosk are snapped onto the nearest street at load, the path is an L/Z along streets. Never draw straight diagonals across blocks again.
- `home2` / `row` / `sync` — nearest kiosks sheet. `bindSheetDrag()` — swipe the sheet down to see the full map, up/tap to restore.
- `walk2`, `codePay` + `payPick`/`bindPayPick` (inline payment method picker), `showCode`, `codeCard`, `arrived`.
- `return2`, `rrow`, `keepLonger`, `insertWait` (return arrival step), `receipt2` (+ `burst()` confetti).
- `takeStep`, `chargingStep` (plays `media/charging.mp4`, the Blender clip), `swapFlow` (ROUND 3 glanceable swap).
- Side panel demo list: `#flow` — now **10 steps** only (see §5).
- Test scripts Claude used: Playwright `t3x.cjs/t4x.cjs` (`node t45.cjs` takes screenshots of the phone into `/mnt/user-data/outputs/check/`). Re-create similar ones locally; `require('playwright')`.

### SwiftUI layout
- `App/ChargeFuzeApp.swift` — RootView: `LogoSplashView → SignInView → LocationStepView → MainTabView`.
- `Views/MainTabView.swift` — **no TabView** (Vu asked to remove navigation + search). Shows `NearbyHomeView(.rent)` / `NearbyHomeView(.ret)` / `MapScreen` + a rental accessory capsule; sheets: account, receipt; covers: `WalkView`.
- `Views/Map/NearbyHomeView.swift` — map + list sheet (`collapsed` state = swipe down for full map), `KioskPin` (standing 3D kiosk + badge, anchor `.bottom`), `WalkCallout`, `KeepLongerSheet`, `ReturnReceiptSheet` (with `BoltConfetti`).
- `Views/Directions/WalkView.swift` — walking (MKDirections walking route = real streets), pay sheet with inline payment picker, `CodeBox`, `ArrivalView`, `ReturnArrivalView`.
- `Views/Rent/SwapView.swift` — glanceable swap (beacon, 3-step progress, voice cues via AVSpeechSynthesizer, auto-advance).
- `Views/Rent/RentFlowView.swift` — `ChargingStep` plays `Resources/Videos/charging.mp4` + confetti.
- `Model/AppModel.swift` — state + flow functions (`buyUnlockCode`, `arrived(at:)`, `returnLocked(_:slot:)`, `returnHere`, `leaveWalk(then:)`, `keepHours`, `lateFeeFrom` …). `Model/Models.swift` — `Station.kioskType` / `kioskImage` (`Kiosk3D`, `Kiosk3D_mini/tower/wide`).
- Icons: Lucide SVGs in `Assets.xcassets/Lucide`, mapped from SF-style names in `Components/Lucide.swift` (add new names there).
- **Nothing has been compiled yet.** First job for an engineer/Codex with Xcode: build, fix compile errors, run on iOS 26 simulator.

## 3. Blender render pipeline (charging clip)

Run Blender in **background subprocesses** (Vu prefers not to have his UI taken over):
```
/Applications/Blender.app/Contents/MacOS/Blender -b _vert/kiosk_vert.blend --python _vert/setup_back.py \
  -o _vert/seqNN/f_#### -F PNG -s 488 -e 600 -a      # run a 2nd process for 601-700 in parallel
```
Then encode (frames 488–700 = 213 frames, 30 fps):
```
ffmpeg -framerate 30 -start_number 488 -i _vert/seqNN/f_%04d.png -frames:v 213 \
  -vf "scale=888:1924,format=yuv420p" -c:v libx264 -crf 19 -preset veryfast -movflags +faststart _vert/chargingNN.mp4
```
Copy to `ChargeFuze-prototype/proto/media/charging.mp4` and `ChargeFuzeApp/ChargeFuze/Resources/Videos/charging.mp4`.
**Render all frames of a clip from the same setup** — mixing old `seq4` frames with new ones caused the visible jump Vu called "rung rung".

`setup_back.py` sections (in order): MIRROR_RIGHT, CAMBG, CABLES_V2 (flat ribbon cables), BANK_PROPORTIONS (real bank ≈ 2:1 and 16 mm thick), TILT_V3 (bank tilted 10°, phone straight above the pulled cable, auto-centred), SHALLOW_BACK, BACK_LAYOUT, SIDE_DETAILS (Power On button, USB‑C, jack, pogo pins), BACK_V4 (flat back shading, small port icons), PLUGS_HIDDEN (plugs live under the cover, ribbons dive into a slot; the pulled plug slides out), SMOOTH_CAM (one continuous camera ease, 96 TAA samples).

Real power bank facts (from Vu's photos — keep them true):
- Back: logo "chargeFUZE ⚡" top centre, Rent / Charge / Return text block, "Please secure all charging cords before returning", 3 printed port icons, then **3 flat blue ribbon cables packed close together** that dive under the cover (plugs NOT visible), a dark finger recess, ribbons run to the bottom edge and wrap round it. 4 blue LEDs lower‑left + big white "Return this way" arrow. Regulatory text block right of the cables. Front: QR, Rent/Charge/Return.
- Cables are flat ribbons — they **never fold sharply** (a folded cable breaks). The pulled cable bends in one gentle bow straight up into the phone's bottom port; the phone sits upright, centred, right above the bank.
- Sides: blue Power On button, USB‑C, audio-jack-sized hole; bottom end: pogo pins.

Kiosk icon renders: `_vert/icons/make_icons4.py` (standard kiosk, original lighting). Pins/list use the **standing kiosk image with no tile/background behind it**.

## 4. Vu's standing preferences (learned the hard way)

- Uber-style layout: map on top, compact sheet, one primary button. Minimise navigation; prefer bottom sheets/inline over new screens.
- **Spacing**: never cramped. Cards ≥16–20 px padding, 16 px gaps; list top inset = side inset; no hairline dividers under sheet titles.
- No background tiles behind the 3D kiosk icons. Different kiosk models per venue (standard/tower/mini/wide) on map + list.
- Icons on coloured tiles are **white**.
- Real 3D from Blender over generic illustrations. Animations must be continuous (no jump cuts) and physically correct (cable direction, plug orientation).
- iOS 26 look: Liquid Glass (`.glassEffect`, `.buttonStyle(.glass)`), SF Pro Rounded numbers, 34 px sheet radius, 56 px pill buttons.
- Confetti on rent start and on return receipt.
- Never require a confirmation tap that a dead phone couldn't make.
- Ask Codex (you) for animation/consistency reviews — Vu likes a second opinion, but Claude validates suggestions against the brief.

### Round 4 (client feedback, Nov 3)
- **Checkout = 2 steps in one sheet** (`checkout(s,mode)` in the web, `CheckoutFlow.swift` in Swift), used by scan-to-rent AND "Phone about to die": 1) *Select pricing* — every plan card fully readable (price · max, check-list, lost-charger note), selected = dark outline; 2) *Rent a charger / Pay now, pick up later* — kiosk name + spot + 3D kiosk + kiosk ID, chosen plan again in full (tap → back to pricing), promo code inline, payment inline picker, hold note, then the Rent / Pay button.
- **No slot numbers in the UI.** Any slot works for taking and returning: say "the one that popped out", "any empty slot". Swap beacon shows an arrow/bolt icon, not a number.
- "Phone about to die?" card: neutral white card, Apple-style low-battery icon (grey outline, red sliver), icon aligned with the heading line. Row icons in lists align with their heading, not the row centre.
- Demo list shows short names only: Sign in, Location, Nearest kiosks, Walk, Pay ahead, Arrive, Kiosk didn't release, Renting, Return, Swap charger.

### Round 5 (Nov 3, afternoon)
- Charging clip = `_vert/charging29.mp4` (seq29). `setup_back.py` now ends with **RIBBON_FIX** (the lifted cable is rebuilt as a flat mesh every frame by a `frame_change_pre` handler: constant width, no twist) and **RECESS_FIX** (black, rounded finger recess). Plugs stay hidden under the cover (PLUGS_HIDDEN).
- Checkout header = venue + "spot · kiosk ID" + close only (no back button, no kiosk image); tap the plan row to change plan. Title sits 20 pt from the sheet top (= side margin). Warnings sit in a soft orange box with an alert icon.
- Swap HUD: capsule container, round beacon (concentric), anchored to the bottom; "Not clicking?" lives inside the HUD; Done button never overflows.
- Return sheet: title + live time·cost pill; under it one line "No late fee until … · Need more time?" (replaces the big row).
- Prototype status bar uses real iOS glyphs (signal, Wi‑Fi, battery).
- Map: pan is clamped so the map edge never shows; collapsing the sheet resets the map to fit.

### Round 6 — REAL_DETAILS from photos IMG_0110–0124 (end of `setup_back.py`)
Round blue Power On button + small round hole near the bottom end on one long side, "Power On" printed along that side with a small arrow; round hole + USB-C on the other side; 3 gold pogo pins each side of the cables on the bottom end; glowing blue light bar on the top end; 3 of the 4 back LEDs lit blue; chunky white block arrow "Return this way". "Need more time?" row on the return sheet was restored (Vu preferred the original row). The walk ETA callout flips to the right of the dot when it would run off the map.

### Round 7 — PLUG_SLOT_V2 (IMG_0124 close-up)
Each cable = narrow flat ribbon (5.8 mm) that widens with concave shoulders into a wide flat boot (9.5 mm); the boot pushes into its own rectangular slot under the port icon, metal plug hidden inside. Cable pitch 11 mm (boots almost touch). Dark rounded finger bay right under the boots. The pulled cable's boot sits in its slot at rest, the metal tip only appears once it lifts out. Prototype map: locate button recentres on the user, the map can be dragged (pins don't get selected/dragged as images).

### Round 8
- NECK_V3: ribbon → boot is a long smooth S-shaped bottle neck (smootherstep over 8 mm), smooth-shaded — matches the close-up photo.
- Walk ETA label sits beside the route at about half way, never on top of the line: it tries both sides and several points along the route, avoiding the line, you and (if possible) the kiosks. Swift: anchored above the route midpoint.
- `index.html` now starts with `<meta charset="utf-8">` (without it a local file:// open can show mojibake).

### Round 9 — TRAY_V3 (empty-tray photo)
The cables sit in ONE recessed tray (~3.4 mm deep, 33 mm wide) that runs from the bottom end up to the port icons. Inside it: two raised ribs forming the three cable channels; a raised, slightly lighter platform with a screw hole; two short fingers on the platform forming the three boot slots under the icons; round finger notches (r ≈ 7 mm) cut into both long sides of the tray next to the platform. Older pocket/ear/ledge/groove cutters are disabled (not deleted).

### Round 10 — faster plug-in (SUPERSEDED: frame-dropping made the background judder)
`charging35.mp4` = seq34 retimed with `_vert/fast_list.txt` (ffmpeg concat): frames 488–579 normal, 580–640 (cable up + into the phone) 2× faster, 641–700 1.6× faster, short hold at the end. 7.1 s → 5.6 s. Re-run the same list after any re-render.

### Round 11
- Speed-up is now done IN the animation: `setup_back.py` ends with RETIME (every keyframe after frame 560 compressed to 60 %, so 700 → 644). Render 488–644, encode with `seq35_list.txt` (adds an 8-frame hold). Never speed up by dropping frames again.
- Swap voice: clear female voice, best quality available (web: Ava/Jenny/Aria Natural, then Apple Ava/Zoe/Samantha; Swift: Ava/Zoe/Samantha premium). Friendlier lines ("Pop it back into any empty slot…").

### Round 12 — walk UI like Apple Maps (Vu liked that popup)
- Turn card: close button on its own, then a light glass card under it: blue 58 pt tile with a white turn arrow, BIG distance to the next turn in feet, instruction under it.
- Walk card: ETA in brand blue, "0.4 mi · arrive 7:44 PM", and a "Look Around" pill button on the right (NO inline picture — Vu: just a button). Tap → full-screen 360° view. Swift: `.lookAroundViewer` with an `MKLookAroundSceneRequest` scene at the kiosk (button disabled when Apple has no imagery). Web: `lookAround()` full-screen drag-to-pan viewer using `media/spot.jpg` (real chargeFUZE booth photo from Vu), with compass + hint. The turn tile is BLACK, not blue.

### Round 13 — when does a swap happen?
1) "Charger not working?" in the rental card → "What's wrong?" sheet: not charging my phone / cable or plug damaged / empty or running low / hot or swollen (red: stop using it, no charge) / something else (→ Help).
2) Auto-detect: after pickup the app watches the phone's battery state (`UIDevice.batteryState`); still `.unplugged` after ~2 min → "Your phone isn't charging" prompt (web demo: iOS-style banner).
Then: at a kiosk (≤40 m) → "Swap here" → SwapView. Away → "Go swap at <nearest kiosk with a full charger>" → walk there (faulty time stops counting) → arrival opens the swap screen instead of the rent arrival. Swift: `SwapReasonSheet.swift`, `AppModel.watchCharging()`, `showSwapReasons`, `swapAuto`, `swapOnArrival`. Web: `swapWhy()`, `notChargingBanner()`, demo step 10 starts with the auto-detect banner.

### Round 14 — feedback from Chinh (product), Nov 4
1. **Phone only, no Google** (phone lets us reach people who keep a charger; SMS code autofills; emails are too easy to farm for promos).
2. **No sign-in at launch**: splash → location → map. Sign-in is asked only at checkout (rent or pay ahead) as a sheet: phone → code with the "From Messages" autofill chip → straight back into checkout. Web `loginSheet()` wraps `checkout()`; Swift `CheckoutFlow` shows `SignInView` while `!model.signedIn`.
3. **Home shows what a dying-phone user needs at once**: nearest kiosk + its route + Go + Scan. The sheet peeks with just that kiosk; swipe up (or "N more nearby") for up to 10. Three sheet states: mini (full map) / peek / full.
4. **No payment row on the home sheet** — payment is changed at checkout.
5. **Return is guided like renting**: full-screen insert clip + the same glass HUD as Swap ("Push it in · any empty slot, logo facing you" → "Locked in", confetti) → receipt.
6. **Visual fix guides by error type, not the chatbot**: `fixGuide()` / `FixGuide.swift` with kinds noEject (kiosk didn't release → "Release another charger" / "Cancel · no charge"), wontInsert (logo facing you, cable end first, push until click), notCharging (plug fully in, press Power On, then swap). Hooked to: eject failure, "Won't go in?" on return, "Not clicking?" in swap, "It's not charging my phone" in the swap reasons.
7. **Stop the route**: red "End" pill in the walk card (+ X in the turn card).
Reference: the client's current app (iPhone Mirroring) home = map + one bottom card "Nearest · <venue> · 3 min walk · N chargers" + Scan; detail sheet with Start walking / Scan to rent; walking view has an X to stop.

### Audit (Nov 4)
Removed the leftover slot number in the rental card; the rental map uses the same top-right locate button as home (help/headset chat button removed, web + Swift MapScreen); side-panel notes rewritten to the current flow; Swift "I'm here" on the return sheet opens the guided ReturnArrivalView instead of finishing silently. Eject/insert clips re-rendered with the current setup (`_vert/seq37`, frames 455–490; eject = 459→488, insert = 488→459, 4-frame lead, 14-frame hold, 6-frame crossfade, 54 frames @30 fps → `_vert/eject2.mp4`, `insert2.mp4`). **Swift BUILDS** (Nov 4) with `/Users/vunguyen/Desktop/Xcode-beta.app` (Xcode 27.3): `DEVELOPER_DIR=…/Xcode-beta.app/Contents/Developer xcodebuild -project ChargeFuzeApp/ChargeFuze.xcodeproj -scheme ChargeFuze -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build` → BUILD SUCCEEDED (fixed: `player.insert(_:after:)`, a stray modifier line in TakeStep). No simulator runtime installed yet (`xcodebuild -downloadPlatform iOS` to run it). `SwapReasonSheet` rows were split so the type checker doesn't time out.

### Round 15 — 3D city + directions like CF Demo
Swift: walk map `.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll)`; overview first, then a follow camera `MapCamera(distance: 420, pitch: 60, heading: route bearing)` updated each step. Home map uses the same muted realistic style (flat camera). Web: `city3d()` adds extruded buildings + trees on the street blocks and tilts the map (CSS `rotate: x 54deg`, perspective) while walking; pins/callouts/puck counter-rotate to stand up; camera follows the puck (`f2center`).

### Round 16 — walk view matches CF Demo
Web `cityHTML()` v2: street-level zoom (×2.9), light sidewalks under wide grey roads, zebra crosswalks at every corner, street names printed on the road (S OLIVE ST, W 4TH ST…), buildings filling each block (1–3 per block, white tops, grey sides, 40–190 px tall), rows of street trees on the sidewalks, blue dot with a wide halo, thin route line (`calc(7px / var(--z))`). Swift follow camera: distance 280 m, pitch 50°, heading = route bearing (Apple 3D muted map, like CF Demo). Build still succeeds.

### Round 17 — navigation MOVEMENT like CF Demo (audited frame by frame via iPhone Mirroring)
CF Demo: overview → ~1.5 s fly-down into a close, tilted (~50–58°) camera; the blue dot is LOCKED on screen (centre, ~70 % down, just above the card) and the map slides + turns under it (course-up: the way you walk always points up, corners turn smoothly); only the route AHEAD is drawn (nothing behind the dot, no footsteps, no ETA callout); turn card counts the distance down to the next maneuver; continuous per-frame motion.
Web: `navRun(s)` (round 17 block) replaces the old 120 ms sim + 300 ms `f2center` follow. One rAF loop: camera = `translate(anchor) rotateX(pitch) rotateZ(-heading) scale(s/S) translate(-dot)` on `#zm`, with CSS `zoom: S` (4.2) so the 3D city stays sharp (a transform scale made it blurry); building heights ×0.3 in nav (`--hh`); the dot is an overlay `.navpuck` placed from `#me`'s projected rect; pins billboard via `--bb`; route polyline rewritten each frame to [dot, remaining vertices]; maneuvers computed from the route's real corners. Demo walk 11 s after the intro.
Swift `WalkView`: distance-based interpolation along the MKRoute polyline (steady pace — the old index-based one sped up/slowed down), 33 ms frames with animations disabled, heading = bearing to a point 15 m ahead, smoothed (`lerpAngle`), `followCamera()` looks 40 m ahead (dot sits low), distance 230 m, pitch 58; route ahead only (`ahead`), footsteps removed; turn text/distance from walked distance through `route.steps`. BUILD SUCCEEDED.

### Round 18 — Swift = web, release-ready structure (Nov 4)
**Source layout** (Xcode synchronized folders: moving files needs no .pbxproj edits):
```
ChargeFuze/
  App/ChargeFuzeApp.swift          RootView, `-demo <screen>` launch argument
  Core/Models/                     Station, Rate, Rental… (plain value types), Live Activity attributes
  Core/State/AppModel.swift        @MainActor @Observable app state + flows; owns `services`
  Core/Services/Services.swift     protocols StationService / AuthService / RentalService / KioskEventService,
                                   KioskEvent (code_used, charger_released, charger_taken, charger_inserted, charger_locked…),
                                   Mock* (demo) and Live* (REST) implementations, `Services.current`
  Core/Networking/APIClient.swift  async/await client, typed Endpoint<T>, snake_case JSON, Bearer token, APIError
  Core/Mock/MockData.swift
  DesignSystem/                    Theme, shared components, Lucide icon mapping
  Features/{Onboarding,Home,Walk,Rent,Swap,Return,Account,Help}/
  Resources/Videos/                cam, charging, eject, insert (HEVC)
```
**API integration**: set `API_BASE_URL` in Info.plist (per build configuration) → `Services.current` switches from mock to live. Fill the paths in `Live*Service` with the backend team; views never touch the network. Kiosk events should come from a WebSocket/SSE into `KioskEventService.events(rentalID:)`.
**Swift 6** language mode on all targets (fixed the 5 data-race errors: Live Activity handles are looked up inside their Task; CLLocationManager status read before hopping to the main actor).
**Size**: removed 9 unused views + story/splash/onboard_* videos + unused image sets (moved to `_to_delete/` on the Mac — deletes are blocked there; empty it by hand). Videos re-encoded HEVC (`libx265 -crf 27 -tag:v hvc1`, ~50 % smaller, same look). KioskFront → 720×1440 JPEG (its Contents.json already pointed at .jpg), KioskHero → 256-colour PNG with alpha. Release .app (unstripped, unsigned) 9.2 MB, media ≈ 2.2 MB.
**QA**: `xcrun simctl launch <udid> com.chargefuze.redesign.demo -demo <walk|arrive|signin|checkout|charging|eject|renting|rentalsheet|return|swapwhy|swap>` opens a screen directly. Scripts on the Mac: `_vert/one.sh <screen>` (build + install + screenshot to `_vert/simshots/`), `_vert/shots.sh` (all screens), `_vert/release.sh` (Release build + size). Xcode 27 has no Simulator.app: the simulator window lives in **Device Hub** (`Xcode-beta.app/Contents/Applications/DeviceHub.app`).
**Sync from Claude's sandbox**: always ship a uniquely named tarball to `_sync/` and run `_vert/sync.sh <tgz>` (overwrites files in place with `cat`; re-using the same staged file name delivered stale copies before).
**Parity fixes**: home frames you + nearest kiosk + route (not the whole city), peek tall enough for "N more nearby"; walk arrival = map + ArrivalCard (no white page), camera settles on the kiosk; pay sheet = 2-step CheckoutFlow; renting map uses the 3D kiosk pins; Look Around before End; "Need more time?" icon black, 20 pt above the buttons.
**Rental card (Chan's feedback "less info", web + Swift)**: walk-card format — coloured time (green, orange in the last 5 min of a block), grey line "$1.00 so far · +$1.00 in 29:27", thin progress to the next charge, black "Find a return station", "Charger not working?". Details (picked up, paying with, price, return by) are NOT a toggle: drag the sheet up (Swift: detents `.height(268)` → `.height(560)`, ScrollView + `.presentationContentInteraction(.resizes)`, content top-aligned so the details peek at the bottom; web: the card follows the finger and springs open/closed).
Web walk: `navRun` camera (round 17) + arrival keeps the 3D camera on the ground (kiosk drawn as an overlay above the puck), CF-style parks/plazas and clumpy sphere trees.

**Rental card, details control (Vu, Nov 4 noon)**: no text hint near the bottom edge (too close to the Home bar, easy mis-touch). The top-right round button is the details control: chevron.up bouncing every ~2.5 s until opened (SF `symbolEffect(.bounce.up, .repeat(.periodic))` / CSS `r3nudge`), rotates to chevron.down when open; dragging the sheet up/down does the same; minimise = swipe down. Swift: detents live inside `ActiveRentalSheet` (`compact .height(206)` ends right under "Charger not working?", `expanded .height(560)`, selection-bound so the button animates them); ScrollView with scrolling OFF so every drag resizes the sheet. Home/return sheet peek uses `.fixedSize(vertical:)` so gaps stay even.

**Bottom cards (Vu, Nov 4)**: every bottom card/sheet floats with the SAME gap at the sides and the bottom (`.floatingAtBottom(8)` in DesignSystem/Components.swift: negative bottom padding = gap − Home-indicator inset, so the card dips into that area; keep ~20 pt under its own buttons). Shape `.bottomCard` = top 34 / bottom 46 (concentric with the screen corners). Used by home/return sheet, walk card, arrival card, scan footer (8) and the renting pill (12). Look Around = one line, 40 pt like End. Kiosk list: no blue outline on the single peek row (Faster says it), white rows, picked row in the full list = 1.5 pt dark outline; "N more nearby" and the scan button are neutral (grey/ink) — blue only for the main CTA and the Faster tag. QA screen `-demo scan` added.

**Swift polish (Nov 4, 12:30–12:50)**: control sizes iOS 26/27 — capsule actions `Theme.buttonHeight` 48, round icon buttons 44 (`Theme.iconButton`); icons in glass buttons use `.tint(.primary)` (ink on light glass, white on dark glass; scan screen icons forced white); the locate arrow stays brand blue (Apple Maps convention). Type: nothing under 11 pt; secondary text in cards ≥ footnote (13). Sign-in sheet hugs its content (`onGeometryChange` → `.presentationDetents([.height(h)])`, solid background). Scan footer: explicit radii + 16 pt gaps (full-screen covers have no container shape for `ConcentricRectangle`). Maps zoom: pinch + `MapZoomControl` (+/−) on home, walk and renting maps; on the walk, any pinch/drag pauses the follow camera and shows a "Re-center" button; +/− while following changes the follow distance. **Exact kiosk spot**: Apple's walking route ends at the street, so a dashed last leg goes to `station.coordinate` with a pulsing `ExactSpotPulse` under the pin; the last instruction reads "Go inside · <spot>". **Look Around only on arrival**: removed from the walk card; the arrival card shows "Inside · <spot>" + "See the spot · 360°" (`SpotViewer`, drag to turn, photo `SpotPhoto`).

**Route + list (Nov 4, ~13:00)**: `MKPolyline.trimmed(toward:)` cuts Apple's walking route at the point closest to the kiosk (it can run past the venue); a dashed leg goes from there into `station.coordinate`; no extra blue dot under the kiosk (it read as "you"). `WalkDirections.route` retries once (MapKit throttles bursts) and falls back to a direct line, so a path is always drawn. Kiosk rows: two aligned rows — name ↔ price on one baseline (name 1 line, tail "…"), tag + "2 min · 8 ready" ↔ "/30 min"; sheet title `.headline`; list insets 10, row padding 12, row radius 24. Arrival "See the spot · 360°" opens Apple Look Around (`MKLookAroundSceneRequest` at the kiosk); the booth photo only where Apple has no imagery. QA args: `-collapsed`, `-expanded`.

**Nov 4 ~13:20**: Buttons are 44 pt everywhere (`Theme.buttonHeight` = 44), titles one line (shrink to 0.8, never wrap); "I'm here" is a 44 pt glass capsule beside the Go button. Walk goes all the way IN: the dot walks the street part, then the dashed leg to `station.coordinate` (the leg shrinks from you to the kiosk); arrival (and "See the spot · 360°") only at the kiosk. Checkout like the web: pricing sheet `.fraction(0.8)` (scrolls), summary hugs its content (measured), Apple Pay = black "Rent/Pay with  Pay" capsule; sign-in = one combined "US +1 | number" field on a grey fill, lock note, blue "Use the demo number"; code step has the close button, 4 left-aligned boxes and a "From Messages 1234" chip. Rental bar 64 pt, 16 pt gaps, bigger type, separate green "Return" button; rental details expanded detent = measured content height.

**Nov 4 ~13:30**: SF Symbols replace Lucide app-wide (semibold); `FilledCapsuleStyle` / `GlassCircleStyle` give exact 44 pt buttons (system glass styles add outer padding); `Theme.brandSoft` is neutral grey; code box + waiting box neutral; peek kiosk row on a light white card; profile button top-aligned with the locate column; arrival card = one header (✓ You've arrived · venue · Inside · spot) + small "360°" button top-right + Scan; collapsed home sheet has even padding; `Theme.cardInset` 16 for all bottom cards. QA `-demo code`.

## 5. Demo list (side panel of the prototype) — trimmed for client review
1 Open app · 2D logo, sign in · 2 Location permission · 3 Nearest kiosks · Faster · 4 Walk there · 2D route · 5 Phone dying · pay, get a code · 6 Arrived · scan or type the code · 7 Kiosk didn't release · retry · 8 While renting · keep it longer · 9 Return · any kiosk, any slot · 10 Charger not working · swap it.
Removed (not part of this round or duplicates): Help, AI voice assistant, Home Screen, Lock Screen, "Phone at 30%" (duplicate of 5), "3D directions" (duplicate of 4). The code for them is still in the file, just not linked.

## 6. Open items / next steps
1. **Compile the SwiftUI app** in Xcode (iOS 26 SDK) and fix errors; Claude never built it.
2. The eject clip (`media/eject.mp4`, used by "kiosk didn't release" and swap) and `story.mp4` were rendered with the OLD power-bank model. Re-render them with the current `setup_back.py` look so all clips match (plugs hidden, correct back).
3. The hand-off from the eject clip to `charging.mp4` has a small brightness/sample mismatch (old vs new render) — fixed by item 2.
4. Backend events the UI assumes (document for engineering): `code_used`, `charger_released(slot)`, `charger_taken`, `charger_inserted(slot)`, `charger_locked(slot)` for return, swap `faulty_seated` → `new_released` → `new_taken`. Today they are simulated with timers.
5. Discovery work (see §7): set an outcome metric and test the riskiest assumptions with real users.

## 7. Review against *Continuous Discovery Habits* (Teresa Torres)

What the workflow already does well
- **Outcome-oriented brief**: the boss framed it as "rent a charger as fast as possible" (time-to-charge), not as a feature list — that is a product outcome.
- **Visual, collaborative thinking**: flows are mapped end-to-end in a clickable prototype that the boss/client can tap through; feedback loops are short (Vu → Claude → Codex review).
- **Compare and contrast**: pin styles, swap screen, return flow were explored as options before picking one (Codex was asked to rank alternatives).
- **Identifying assumptions**: several were made explicit and designed around — "the phone may be dead, so no confirm tap", "users can return to any slot", "users need more time rather than a reserved slot".

What is missing
- **No weekly customer touchpoints.** Every decision so far came from the team (Vu, boss, Claude, Codex). The book's definition of continuous discovery = weekly contact with customers, by the team building the product, small research activities, toward a desired outcome.
- **No measurable outcome yet.** Pick one: median *time from app open → charger in hand*, % of rentals started with ≤10 % battery that succeed, failed-eject rate, late returns.
- **No opportunity solution tree.** Opportunities (dead phone, can't find kiosk, kiosk didn't release, fear of late fees, can't find empty slot) should be written as customer needs and prioritised before more solutions are polished.
- **Assumptions are not tested** — e.g. "people remember a 4-digit code", "people understand double-tap the kiosk screen", "a 3D kiosk pin is recognisable", "voice cues help during swap". These are desirability/usability assumptions that cheap tests can de-risk.
- **Story-based interviewing**: no interview snapshots of real "last time your phone died" stories.

Recommendations (smallest useful steps)
1. Write the outcome + a baseline (from current app analytics if any).
2. 5 story-based interviews ("Tell me about the last time your phone was about to die when you were out") → interview snapshots → experience map.
3. Build an OST with 3–5 opportunities; pick one target opportunity.
4. Assumption tests (1 week): unmoderated test of the prototype (task: "your phone is at 3 %, get a charger") measuring time + errors; a code-memory test (show code, distract 2 min, ask to type it); a 5-second test of the map pins.
5. After launch: instrument the funnel (open → kiosk chosen → arrived → charger out) and the failure states, review weekly.
