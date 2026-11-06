import SwiftUI
import MapKit

/// Walking to the kiosk like CF Demo: overview, fly-in, then a close, tilted, course-up camera glued to your dot;
/// only the route ahead is drawn. "Phone about to die?" = pay now, get a 4-digit code.


struct WalkView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let station: Station
    var origin: CLLocation? = nil

    private var startLocation: CLLocation { origin ?? model.userLocation }

    @State private var camera: MapCameraPosition = .automatic
    @State private var route: MKRoute?           // Apple's route (steps, distance) when available
    @State private var routeUnavailable = false
    @State private var routeAttempt = 0
    @State private var me: CLLocationCoordinate2D?
    @State private var ahead: [CLLocationCoordinate2D] = []   // only the street route still in front of you (like CF Demo)
    @State private var progress: Double = 0
    @State private var pickPay = false
    @State private var following = true        // camera glued to you; pinch/drag pauses it
    @State private var followDistance: Double = 230
    @State private var lastCamera: MapCamera?
    @State private var showPay = false
    @State private var arrived = false
    @State private var approachingKiosk = false
    @State private var showReturnGuide = false
    @State private var returnSlot: Int?
    @State private var returnNeedsVerification = false
    @State private var lookScene: MKLookAroundScene?
    @State private var showLook = false
    @State private var showSpot = false

    private var isLookingAround: Bool { showLook || showSpot }
    private var canLookAround: Bool {
        let coordinate = (model.isDemo ? me : nil) ?? startLocation.coordinate
        return WalkDirections.distance(coordinate, station.coordinate) <= 45
    }

    var body: some View {
        Map(position: $camera) {
            if ahead.count > 1 {
                MapPolyline(coordinates: ahead).stroke(.white, style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: ahead).stroke(Theme.brand, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            }
            if let points = route?.polyline.walkingCoordinates {
                if me == nil, let start = points.first,
                   WalkDirections.distance(startLocation.coordinate, start) > 2 {
                    MapPolyline(coordinates: [startLocation.coordinate, start])
                        .stroke(Theme.brand.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 6]))
                }
                if let end = points.last, requiresVenueHandoff, !arrived {
                    Annotation("Walking route ends", coordinate: end) { RouteEndpoint() }
                        .annotationTitles(.hidden)
                }
            }
            if approachingKiosk, let me {
                MapPolyline(coordinates: [me, station.coordinate])
                    .stroke(Theme.brand, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 8]))
            }
            Annotation(station.venue, coordinate: station.coordinate, anchor: .bottom) { KioskPin(station: station, selected: true) }
                .annotationTitles(.hidden)
            Annotation("You", coordinate: me ?? startLocation.coordinate) { UserDot() }
        }
        // At a venue, a flat map keeps the road endpoint and indoor kiosk readable.
        .mapStyle(.standard(elevation: arrived && requiresVenueHandoff ? .flat : .realistic,
                            emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { }
        .onMapCameraChange(frequency: .onEnd) { lastCamera = $0.camera }
        .simultaneousGesture(MagnifyGesture().onChanged { _ in following = false })
        .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in following = false })
        .overlay(alignment: .trailing) {
            VStack(spacing: 10) {
                MapZoomControl(zoomIn: { zoom(0.65) }, zoomOut: { zoom(1.5) })
                if !following {
                    Button { withAnimation(.smooth) { following = true } } label: {
                        AppIcon("location.fill", size: 18).foregroundStyle(Theme.brand).frame(width: 44, height: 44)
                    }
                    .buttonStyle(GlassCircleStyle()).accessibilityLabel("Re-center")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.trailing, 16).padding(.bottom, 80)
            .animation(.smooth, value: following)
        }
        .overlay(alignment: .topLeading) {
            if arrived {
                Button { dismiss() } label: { AppIcon("xmark", size: 16) }
                    .buttonStyle(GlassCircleStyle()).accessibilityLabel("Close")
                    .padding(.leading, Theme.cardInset)
            } else if route != nil {
                turnCard
            }
        }
        .safeAreaInset(edge: .bottom) { bottomPanel }
        .animation(.smooth(duration: 0.35), value: showArrival)
        .sheet(isPresented: $showPay) { payCode }
        .fullScreenCover(isPresented: $showReturnGuide, onDismiss: finishReturnGuide) {
            ReturnArrivalView(station: station, onLocked: { slot in
                returnSlot = slot
                showReturnGuide = false
            }, onUnconfirmed: {
                returnNeedsVerification = true
                showReturnGuide = false
            })
        }
        .lookAroundViewer(isPresented: $showLook, initialScene: lookScene)
        .fullScreenCover(isPresented: $showSpot) { SpotViewer(station: station) }
        .task(id: route != nil) {
            guard route != nil || canLookAround else { return }
            let coordinate = route?.polyline.walkingCoordinates.last ?? station.coordinate
            let scene = try? await MKLookAroundSceneRequest(coordinate: coordinate).scene
            if !Task.isCancelled { lookScene = scene }
        }
        .task(id: routeAttempt) { await load() }
        .sensoryFeedback(.success, trigger: arrived)
    }

    private var bottomPanel: some View {
        let lookAction: (() -> Void)? = canLookAround ? { openLookAround() } : nil
        return Group {
            if showArrival {
                ArrivalCard(station: station, isLookingAround: isLookingAround, onLookAround: lookAction)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                card
            }
        }
        .floatingAtBottom(arrived ? 8 : Theme.cardInset)
    }

    private func finishReturnGuide() {
        let slot = returnSlot
        let needsVerification = returnNeedsVerification
        model.leaveWalk {
            if let slot { model.returnLocked(station, slot: slot) }
            else if needsVerification { model.verifyUnconfirmedReturn(at: station) }
        }
    }

    private var turnCard: some View {
        HStack(alignment: .center, spacing: 14) {
            AppIcon(nextTurnIcon, size: 28).foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Theme.ink, in: .rect(cornerRadius: Theme.fieldRadius, style: .circular))
            VStack(alignment: .leading, spacing: 2) {
                Text(nextTurnDistance).font(.system(size: 28, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(nextTurnText.replacingOccurrences(of: "Arrive at ", with: ""))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { dismiss() } label: { AppIcon("xmark", size: 16) }
                .buttonStyle(GlassCircleStyle()).accessibilityLabel("Close directions")
        }
        .padding(Theme.cardInset)
        .background(.regularMaterial, in: .rect(cornerRadius: Theme.turnCardRadius, style: .circular))
        .padding(.horizontal, Theme.cardInset)
    }

    /// Where we are in the route's steps: the step being walked, and metres left in it.
    private var stepNow: (index: Int, left: Double)? {
        guard let route else { return nil }
        let walked = progress * route.distance; var acc = 0.0
        for (i, st) in route.steps.enumerated() where st.distance > 0 {
            acc += st.distance
            if acc > walked { return (i, acc - walked) }
        }
        return nil
    }
    /// Feet to the next turn (US).
    private var nextTurnDistance: String {
        guard let now = stepNow else { return route == nil ? "—" : "Arriving" }
        let ft = now.left * 3.281
        return ft >= 1000 ? String(format: "%.1f mi", now.left / 1609) : "\(max(10, Int((ft / 10).rounded()) * 10)) ft"
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    if let route {
                        Text("\(remaining) min").font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.brand).contentTransition(.numericText())
                        Text("\(String(format: "%.1f", route.distance * (1 - progress) / 1609)) mi · arrive \(Date.now.addingTimeInterval(Double(remaining) * 60).shortTime)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text(routeUnavailable ? "Route unavailable" : "Finding a walking route…").font(.headline)
                        Text(station.kioskLocation).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if canLookAround { LookAroundButton(action: openLookAround) }
                Button { arriveNow() } label: {
                    Text("I'm at kiosk").font(.headline).lineLimit(1).padding(.horizontal, 18).frame(height: Theme.buttonHeight)
                }
                .buttonStyle(FilledCapsuleStyle(tint: Theme.brand))
                .accessibilityLabel("I'm at kiosk")
            }

            if route != nil {
                ProgressView(value: progress)
                    .tint(Theme.brand)
                    .padding(.horizontal, 8)
            }
            if routeUnavailable {
                PrimaryButton(title: "Retry directions") { routeAttempt += 1 }
            }
            if model.activeRental == nil, model.unlockCode(for: station) != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let code = model.unlockCode(for: station, at: context.date) {
                        CodeBox(code: code, station: station, expires: model.unlockCodeExpires)
                    } else {
                        PrimaryButton(title: "Get a new unlock code") { showPay = true }
                    }
                }
            }
            else if model.activeRental == nil, route != nil {
                Button { showPay = true } label: {
                    HStack(alignment: .center, spacing: 12) {
                        LowBatteryIcon()
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Phone about to die?").font(.headline)
                            Text("Get an unlock code before you arrive.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .background(
                        Color(uiColor: .systemBackground),
                        in: .floatingPanel(top: Theme.noticeRadius, minimumBottom: Theme.walkCardRadius - Theme.cardInset)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens checkout for an unlock code")
            }
        }
        .padding(Theme.cardInset)
        .background(.regularMaterial, in: .floatingPanel(top: Theme.walkCardRadius, minimumBottom: Theme.walkCardRadius))
    }

    /// Checkout (pricing → summary) → pay → 4 digits flip in.
    private var payCode: some View {
        CheckoutFlow(station: station, mode: .code, pickupMinutes: remaining) {
            withAnimation(.snappy) { model.buyUnlockCode(at: station) }
            showPay = false
        }
    }

    private var showArrival: Bool { arrived && !model.returnMode && !model.swapOnArrival }
    private var requiresVenueHandoff: Bool {
        guard let end = route?.polyline.walkingCoordinates.last else { return station.isInsideVenue }
        return WalkDirections.needsHandoff(for: station, from: end)
    }

    private func openLookAround() {
        if lookScene != nil { showLook = true }
        else { showSpot = true }
    }

    private var remaining: Int { max(0, Int((((route?.expectedTravelTime ?? 0) / 60) * (1 - progress)).rounded(.up))) }
    /// The maneuver at the end of the step being walked (MKRoute: a step's instructions = what to do as it starts).
    private var nextTurnText: String {
        if approachingKiosk { return "Go inside · \(station.kioskLocation)" }
        guard let route, let now = stepNow else { return station.venue }
        let next = route.steps.dropFirst(now.index + 1).first { !$0.instructions.isEmpty }
        return next?.instructions ?? station.venue
    }
    private var nextTurnIcon: String {
        let t = nextTurnText.lowercased()
        return t.contains("right") ? "arrow.turn.up.right" : t.contains("left") ? "arrow.turn.up.left" : "arrow.up"
    }

    /// Compass bearing (degrees) from a to b, for the follow camera.
    static func bearing(_ a: MKMapPoint, _ b: MKMapPoint) -> CLLocationDirection {
        let p1 = a.coordinate, p2 = b.coordinate
        let φ1 = p1.latitude * .pi / 180, φ2 = p2.latitude * .pi / 180, Δλ = (p2.longitude - p1.longitude) * .pi / 180
        let y = sin(Δλ) * cos(φ2), x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Turn the shortest way from a to b by k (0…1).
    static func lerpAngle(_ a: Double, _ b: Double, _ k: Double) -> Double {
        let d = (b - a + 540).truncatingRemainder(dividingBy: 360) - 180
        return (a + d * k + 360).truncatingRemainder(dividingBy: 360)
    }

    /// CF Demo-style follow camera: close, tilted, course-up; the dot sits low on screen
    /// because the camera looks at a point ~40 m ahead of you.
    private func zoom(_ k: Double) {
        if following { followDistance = min(max(followDistance * k, 120), 2_000) }
        else if let c = lastCamera { withAnimation(.smooth(duration: 0.35)) { camera = .camera(c.zoomed(k)) } }
    }

    static func followCamera(_ p: MKMapPoint, heading: Double, distance: Double = 230) -> MapCamera {
        let ppm = MKMapPointsPerMeterAtLatitude(p.coordinate.latitude), r = heading * .pi / 180, ahead = distance * 0.17
        let c = MKMapPoint(x: p.x + sin(r) * ahead * ppm, y: p.y - cos(r) * ahead * ppm)
        return MapCamera(centerCoordinate: c.coordinate, distance: distance, heading: heading, pitch: 58)
    }

    private func load() async {
        routeUnavailable = false
        let result = await WalkDirections.route(from: startLocation, to: station.location)
        guard !Task.isCancelled else { return }
        guard let result else {
            routeUnavailable = true
            camera = .camera(MapCamera(centerCoordinate: station.coordinate, distance: 700))
            return
        }
        let poly = result.polyline
        let pts = poly.walkingCoordinates.map(MKMapPoint.init)
        let n = pts.count
        route = result

        var cum = [0.0]; for i in 1..<n { cum.append(cum[i - 1] + pts[i - 1].distance(to: pts[i])) }
        let total = max(cum[n - 1], 1)
        func at(_ d: Double) -> (p: MKMapPoint, i: Int) {
            let d = min(max(d, 0), total)
            var i = 0; while i < n - 2 && cum[i + 1] < d { i += 1 }
            let l = cum[i + 1] - cum[i], k = l > 0 ? (d - cum[i]) / l : 0
            return (MKMapPoint(x: pts[i].x + (pts[i + 1].x - pts[i].x) * k, y: pts[i].y + (pts[i + 1].y - pts[i].y) * k), i)
        }
        // heading = toward a point ~15 m ahead on the route, so corners are anticipated, not snapped
        func aim(_ d: Double) -> Double { Self.bearing(at(d).p, at(min(total, d + 15)).p) }

        // 1) overview of the whole route, 2) fly down into the tilted follow camera (CF Demo intro)
        camera = .rect(poly.boundingMapRect.insetBy(dx: -300, dy: -500))
        ahead = pts.map(\.coordinate)
        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled else { return }
        var h = aim(0)
        withAnimation(.easeInOut(duration: 1.5)) { camera = .camera(Self.followCamera(pts[0], heading: h)) }
        try? await Task.sleep(for: .milliseconds(1550))

        // Production: drive this from CLLocationManager (location + course) and arrive within ~25 m.
        // Demo: walk the route in ~11 s, one frame every 33 ms, camera glued to the dot.
        let duration = model.demoArriveNow ? 0.05 : 11.0
        var lastTick = Date.now
        var elapsed = 0.0
        model.demoArriveNow = false
        while !Task.isCancelled && !arrived {
            try? await Task.sleep(for: .milliseconds(33))
            guard !Task.isCancelled else { return }
            let now = Date.now
            if !showPay && !isLookingAround { elapsed += now.timeIntervalSince(lastTick) }
            lastTick = now
            if showPay || isLookingAround { continue }
            let t = min(1, elapsed / duration), d = t * total
            let cur = at(d)
            h = Self.lerpAngle(h, aim(d), 0.12)          // smooth turn, ~0.5 s at a corner
            var tx = Transaction(); tx.disablesAnimations = true
            withTransaction(tx) {
                me = cur.p.coordinate; progress = t
                ahead = t < 1 ? [cur.p.coordinate] + pts[(cur.i + 1)...].map(\.coordinate) : []
                if following { camera = .camera(Self.followCamera(cur.p, heading: h, distance: followDistance)) }
            }
            if t >= 1 { break }
        }
        guard !Task.isCancelled, !arrived else { return }   // "I'm at kiosk" already handled arrival
        if model.isDemo, requiresVenueHandoff {
            approachingKiosk = true
            let start = pts[n - 1]
            let end = MKMapPoint(station.coordinate)
            var lastApproachTick = Date.now
            var approachElapsed = 0.0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                let now = Date.now
                if !isLookingAround { approachElapsed += now.timeIntervalSince(lastApproachTick) }
                lastApproachTick = now
                if arrived { return }
                if isLookingAround { continue }
                let fraction = min(1, approachElapsed / 0.9)
                let point = MKMapPoint(x: start.x + (end.x - start.x) * fraction,
                                       y: start.y + (end.y - start.y) * fraction)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    me = point.coordinate
                    camera = .camera(MapCamera(centerCoordinate: point.coordinate, distance: 290))
                }
                if fraction >= 1 { break }
            }
        }
        guard !Task.isCancelled else { return }
        approachingKiosk = false
        withAnimation(.smooth(duration: 0.35)) {
            camera = .camera(MapCamera(centerCoordinate: me ?? station.coordinate, distance: 290))
            arrived = true
        }
        handleArrival()
    }

    /// "I'm at kiosk": the user says they're there (GPS can be off indoors) → same arrival as reaching the end of the route.
    private func arriveNow() {
        guard !arrived else { return }
        approachingKiosk = false
        withAnimation(.smooth(duration: 0.35)) {
            me = station.coordinate
            progress = 1
            ahead = []
            camera = .camera(MapCamera(centerCoordinate: station.coordinate, distance: 290))
            arrived = true
        }
        handleArrival()
    }

    private func handleArrival() {
        if model.swapOnArrival {
            model.leaveWalk { model.showSwap = true }
        } else if model.returnMode {
            showReturnGuide = true
        }
    }
}

/// The four kiosk digits and the illustrated double-tap instruction from the web.
struct CodeBox: View {
    let code: String
    let station: Station
    var expires: Date? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Unlock code").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                if let expires, expires > .now {
                    Label {
                        Text(timerInterval: Date.now...expires, countsDown: true).monospacedDigit()
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.brandSoft, in: .capsule)
                    .accessibilityLabel("Time left to use code")
                }
            }
            UnlockCodeDigits(code: code)
            HStack(spacing: 12) {
                KioskDoubleTapHint(image: station.kioskImage)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Double-tap the kiosk screen").font(.subheadline.weight(.semibold))
                    Text("Then type these 4 digits. The code works even if your phone dies.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(Theme.cardInset)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.groupRadius, style: .circular))
        .sensoryFeedback(.success, trigger: code)
    }
}

private struct KioskDoubleTapHint: View {
    let image: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var play = false

    var body: some View {
        Image(image).resizable().scaledToFit()
            .frame(width: 38, height: 52)
            .overlay(alignment: .top) {
                if reduceMotion {
                    Circle().strokeBorder(Theme.brand, lineWidth: 1.5)
                        .frame(width: 10, height: 10).offset(y: 6)
                } else {
                    Color.clear.frame(width: 14, height: 14)
                        .keyframeAnimator(initialValue: 0.0, trigger: play) { _, elapsed in
                            let beat = elapsed.truncatingRemainder(dividingBy: 1.6)
                            ZStack {
                                ripple(beat / 0.352, startScale: 0.6, endScale: 1.4)
                                ripple((beat - 0.352) / 0.32, startScale: 0.8, endScale: 1.5)
                            }
                        } keyframes: { _ in
                            MoveKeyframe(0.0)
                            LinearKeyframe(3.2, duration: 3.2)
                        }
                        .offset(y: 4.4)
                        .task { play.toggle() }
                }
            }
            .accessibilityHidden(true)
    }

    nonisolated private func ripple(_ phase: Double, startScale: Double, endScale: Double) -> some View {
        let progress = min(1, max(0, phase))
        let eased = 1 - (1 - progress) * (1 - progress)
        return Circle().strokeBorder(Theme.brand, lineWidth: 2)
            .frame(width: 14, height: 14)
            .scaleEffect(startScale + (endScale - startScale) * eased)
            .opacity(sin(.pi * progress))
    }
}

private struct LookAroundButton: View {
    var expanded = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if expanded {
                    Label("Look Around", systemImage: "binoculars")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                } else {
                    VStack(spacing: 1) {
                        Image(systemName: "binoculars").font(.system(size: 15, weight: .semibold))
                        Text("360°").font(.caption2.weight(.semibold))
                    }
                    .frame(width: Theme.iconButton)
                }
            }
            .foregroundStyle(Theme.brand)
            .frame(minHeight: Theme.iconButton)
            .background(Theme.brandSoft, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Look Around")
    }
}

/// Arrived (rent): the map stays, this card replaces the walk card — same as the web prototype.
struct ArrivalCard: View {
    @Environment(AppModel.self) private var model
    let station: Station
    let isLookingAround: Bool
    let onLookAround: (() -> Void)?
    @State private var accepted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(station.kioskImage).resizable().scaledToFit().frame(width: 30, height: 48)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(station.venue).font(.headline).accessibilityAddTraits(.isHeader)
                        Text(station.kioskLocation).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    Label("You've arrived", symbol: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.success)
                    Spacer(minLength: 4)
                    if let onLookAround { LookAroundButton(expanded: true, action: onLookAround) }
                }
            }
            if let code = model.unlockCode(for: station) {
                CodeBox(code: code, station: station)
            }
            if let code = model.unlockCode(for: station) {
                HStack(spacing: 14) {
                    if accepted {
                        AppIcon("checkmark", size: 18).foregroundStyle(.white).frame(width: 36, height: 36).background(Theme.success, in: .circle)
                            .transition(.scale.combined(with: .opacity))
                    } else if model.isDemo {
                        ProgressView()
                    } else {
                        Image(systemName: "keypad").foregroundStyle(Theme.brand)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(accepted ? "Code accepted" : model.isDemo ? "Waiting for the kiosk" : "Enter the code at the kiosk").font(.headline)
                        Text(accepted ? "Pull out the charger that popped up." : "The charger pops out when the code is typed, even if your phone is off.")
                            .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16).background(accepted ? Theme.success.opacity(0.1) : Color(uiColor: .systemBackground), in: .rect(cornerRadius: Theme.noticeRadius, style: .circular))
                .task(id: model.isDemo && !isLookingAround) {
                    guard model.isDemo, !isLookingAround else { return }
                    accepted = false
                    do { try await Task.sleep(for: .seconds(3.6)) } catch { return }
                    guard model.unlockCode(for: station) == code else { return }
                    withAnimation(.spring(duration: 0.25)) { accepted = true }
                    do { try await Task.sleep(for: .seconds(0.9)) } catch { return }
                    model.leaveWalk { model.redeemDemoUnlockCode(at: station) }
                }
                Button { model.leaveWalk { model.startRentFlow(at: station) } } label: { Label("Scan instead", symbol: "qrcode.viewfinder") }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            } else {
                Text("Have a code? Double-tap the kiosk screen to enter it.")
                    .font(.footnote).foregroundStyle(.secondary)
                PrimaryButton(title: "Scan the kiosk QR", systemImage: "qrcode.viewfinder") {
                    model.leaveWalk { model.startRentFlow(at: station) }
                }
            }
        }
        .padding(Theme.cardInset)
        .background(.regularMaterial, in: .floatingPanel(top: Theme.walkCardRadius, minimumBottom: Theme.walkCardRadius))

    }
}

/// Pulsing ring on the exact kiosk spot (under the 3D pin), so it reads as "here", not "somewhere on this block".
struct ExactSpotPulse: View {
    @State private var on = false
    var body: some View {
        ZStack {
            Circle().fill(Theme.brand.opacity(0.18)).frame(width: 46, height: 46).scaleEffect(on ? 1.25 : 0.7).opacity(on ? 0 : 1)
            Circle().fill(Theme.brand).frame(width: 10, height: 10).overlay(Circle().stroke(.white, lineWidth: 2))
        }
        .onAppear { withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { on = true } }
        .allowsHitTesting(false)
    }
}

/// 360° look at the exact spot (photo of the real booth): drag sideways to turn, like the web viewer.
struct SpotViewer: View {
    @Environment(\.dismiss) private var dismiss
    let station: Station
    @Environment(AppModel.self) private var model
    @State private var offset: CGFloat = 0
    @GestureState private var drag: CGFloat = 0
    var body: some View {
        GeometryReader { g in
            let w = g.size.height * 1.0   // square photo scaled to the screen height
            if model.isDemo {
                Image("SpotPhoto").resizable().scaledToFill().frame(width: w, height: g.size.height)
                .offset(x: max(min(offset + drag, (w - g.size.width) / 2), -(w - g.size.width) / 2))
                .frame(width: g.size.width, height: g.size.height).clipped()
                .gesture(DragGesture().updating($drag) { v, s, _ in s = v.translation.width }
                    .onEnded { v in withAnimation(.smooth) { offset = max(min(offset + v.translation.width, (w - g.size.width) / 2), -(w - g.size.width) / 2) } })
            } else {
                ContentUnavailableView("Look Around unavailable", systemImage: "binoculars",
                                       description: Text(station.kioskLocation))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            HStack {
                Button { dismiss() } label: { AppIcon("xmark", size: 16).foregroundStyle(.white).frame(width: 44, height: 44) }
                    .buttonStyle(GlassCircleStyle())
                Spacer()
                VStack(spacing: 1) {
                    Text(station.venue).font(.subheadline.weight(.semibold))
                    Text(model.isDemo ? "Demo reference photo" : station.kioskLocation).font(.footnote).opacity(0.85)
                }
                .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 6).glassEffect(.regular, in: .capsule)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .environment(\.colorScheme, .dark).padding(.horizontal, 16).padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            if model.isDemo {
                Label("Drag to look around", symbol: "hand.draw").font(.footnote.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 36).glassEffect(.regular, in: .capsule)
                    .environment(\.colorScheme, .dark).padding(.bottom, 24)
            }
        }
        .background(.black)
    }
}

/// Return arrival: show how to push the charger in, wait for the kiosk to report it locked, then hand off to the receipt.
/// Return, guided like renting: full-screen Blender insert clip + one glanceable status (same HUD as Swap).
/// The kiosk's lock event advances it; then confetti and the receipt. "Won't go in?" opens a visual fix guide.
struct ReturnArrivalView: View {
    let station: Station
    var onLocked: (Int) -> Void
    var onUnconfirmed: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var slot: Int? = nil
    @State private var help = false
    @State private var ripple = false

    var body: some View {
        ZStack(alignment: .bottom) {
            LoopingVideoView(name: "insert").ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill((slot == nil ? Theme.brand : Theme.success).opacity(0.22))
                    if slot == nil {
                        Circle().stroke(Color(red: 0.49, green: 0.75, blue: 1).opacity(ripple ? 0 : 0.55), lineWidth: 2).scaleEffect(ripple ? 1.35 : 1)
                    }
                    AppIcon(slot == nil ? "arrow.down" : "checkmark", size: 34)
                        .foregroundStyle(slot == nil ? Color(red: 0.49, green: 0.75, blue: 1) : Color(red: 0.37, green: 0.88, blue: 0.54))
                }
                .frame(width: 68, height: 68)
                VStack(alignment: .leading, spacing: 8) {
                    Text(slot == nil ? "Push it in" : "Locked in").font(.title2.bold())
                    Text(slot == nil ? "Any empty slot · logo facing you" : "Charger returned · billing stopped")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.78))
                    if slot == nil {
                        Button("Won't go in?") { help = true }.font(.subheadline.weight(.semibold)).foregroundStyle(Color(red: 0.62, green: 0.82, blue: 1))
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(Theme.cardInset)
            .background(.regularMaterial, in: Capsule(style: .circular))
            .floatingAtBottom(Theme.cardInset)
            .animation(.spring(duration: 0.45, bounce: 0.35), value: slot)
            if slot != nil { BoltConfetti().allowsHitTesting(false).ignoresSafeArea() }
        }
        .overlay(alignment: .top) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(GlassCircleStyle())
                .accessibilityLabel("Close")
                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { step in
                        Capsule().fill(.white.opacity(step == 0 || slot != nil ? 0.9 : 0.3))
                            .frame(height: 4)
                    }
                }
                .accessibilityLabel(slot == nil ? "Returning charger" : "Return confirmed")
                Color.clear.frame(width: Theme.iconButton, height: Theme.iconButton)
            }
            .padding(.horizontal, Theme.cardInset).padding(.top, 8)
        }
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $help) { FixGuideSheet(kind: .wontInsert).preferredColorScheme(.light) }
        .sensoryFeedback(.success, trigger: slot)
        .onAppear { withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { ripple = true } }
        .task(id: help) {
            guard !help else { return }
            do { try await Task.sleep(for: .seconds(5.2)) } catch { return }
            if model.demoReturnNotConfirmed {
                onUnconfirmed()
                return
            }
            let confirmedSlot = [2, 6, 9, 13, 17].randomElement() ?? 6
            withAnimation { slot = confirmedSlot }
            do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
            onLocked(confirmedSlot)
        }
    }
}
