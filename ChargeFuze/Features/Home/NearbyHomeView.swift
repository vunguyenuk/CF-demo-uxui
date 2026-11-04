import SwiftUI
import MapKit

/// The one screen people see first, laid out like a ride app's trip picker:
/// map with the 5–10 closest kiosks (3D icons), a short list with the fastest one tagged,
/// and one big button. Used for renting and, with `mode: .ret`, for returning.
struct NearbyHomeView: View {
    enum Mode { case rent, ret }
    var mode: Mode = .rent

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition = .automatic
    @State private var lastCamera: MapCamera?
    @State private var pick: String?
    @State private var route: MKRoute?
    @State private var routeReveal = 1.0
    @State private var pinFlashID: String?
    @State private var pinFlashOpacity = 0.0
    @State private var pinTap = 0
    @State private var locationPulse = 0
    @State private var routeUnavailable = false
    @State private var appeared = false
    @State private var showKeep = false
    @State private var returning = false
    @State private var collapsed = false     // swipe the sheet down to see the whole map
    @State private var expanded = false
    @State private var returnToVerify: Station?
    @State private var returnGuide: Station?      // peek = nearest kiosk only; swipe up for up to 10

    private var list: [Station] {
        mode == .rent ? model.nearbyStations : Array(model.returnCandidates.prefix(8))
    }
    private func usable(_ s: Station) -> Bool {
        s.status == .online && (mode == .rent ? s.chargers > 0 : s.returnSlots > 0)
    }
    private var ready: [Station] { list.filter(usable) }
    private var picked: Station? { list.first { $0.id == pick && usable($0) } ?? ready.first }
    private var tint: Color { mode == .rent ? Theme.brand : Theme.success }

    var body: some View {
        Map(position: $camera) {
            Annotation("You", coordinate: model.userLocation.coordinate) { UserDot(pulse: locationPulse) }
            if let route, let p = picked {
                WalkingRouteOverlay(route: route, origin: model.userLocation.coordinate, station: p, reveal: routeReveal)
            }
            ForEach(list) { s in
                Annotation(s.venue, coordinate: s.coordinate, anchor: .bottom) {
                    KioskPin(station: s, count: mode == .rent ? s.chargers : s.returnSlots, tint: tint,
                             selected: s.id == picked?.id, glow: s.id == ready.first?.id)
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                        .animation(.spring(duration: 0.22), value: appeared)
                        .onTapGesture { selectPin(s) }
                }
                .annotationTitles(.hidden)
            }
            if let routeMinutes, let midpoint = routeMidpoint {
                Annotation("", coordinate: midpoint, anchor: .bottom) {
                    WalkCallout(minutes: routeMinutes)
                        .padding(.bottom, 8).allowsHitTesting(false)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { lastCamera = $0.camera }
        .mapControls { MapCompass() }
        .safeAreaInset(edge: .bottom, spacing: 0) { sheet.floatingAtBottom() }
        .fullScreenCover(item: $returnGuide, onDismiss: {
            guard let station = returnToVerify else { return }
            returnToVerify = nil
            model.verifyUnconfirmedReturn(at: station)
        }) { station in
            ReturnArrivalView(station: station, onLocked: { slot in
                returnGuide = nil
                model.returnLocked(station, slot: slot)
            }, onUnconfirmed: {
                returnToVerify = station
                returnGuide = nil
            })
        }
        .overlay(alignment: .top) {
            HStack(alignment: .top) {   // top-aligned: profile sits level with the locate button
                if mode == .rent {
                    Button { model.showAccount = true } label: { AppIcon("person.fill", size: 21).frame(width: 44, height: 44) }
                        .buttonStyle(GlassCircleStyle()).accessibilityLabel("Account")
                } else {
                    Button { withAnimation(.smooth) { model.returnMode = false } } label: { AppIcon("xmark", size: 16).frame(width: 44, height: 44) }
                        .buttonStyle(GlassCircleStyle()).accessibilityLabel("Close")
                }
                Spacer()
                VStack(spacing: 10) {
                    Button(action: recenter) {
                        AppIcon("location.fill", size: 18).foregroundStyle(Theme.brand).frame(width: 44, height: 44)
                    }
                    .buttonStyle(GlassCircleStyle()).accessibilityLabel("My location")
                    MapZoomControl(zoomIn: { zoom(0.6) }, zoomOut: { zoom(1.6) })
                }
            }
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $showKeep) { KeepLongerSheet().presentationDragIndicator(.visible) }
        .task(id: picked?.id) { await loadRoute() }
        .task(id: pinTap) {
            guard pinTap > 0 else { return }
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            withAnimation(.easeOut(duration: 0.21)) { pinFlashOpacity = 0 }
        }
        .onAppear {
            appeared = true
            if ProcessInfo.processInfo.arguments.contains("-collapsed") { collapsed = true }   // QA
            if ProcessInfo.processInfo.arguments.contains("-expanded") { expanded = true }     // QA
        }
    }

    // MARK: Bottom sheet (title, list, payment / need-more-time row, one button)

    private var sheet: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
            Capsule().fill(.quaternary).frame(width: 36, height: 5).padding(.top, 6)
            if mode == .ret, let r = model.activeRental {
                // one compact row: title left, live time · cost pill right
                HStack(spacing: 12) {
                    Text("Return to any kiosk").font(.headline)
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        HStack(spacing: 6) {
                            Text(r.elapsed(at: ctx.date).clock).fontWeight(.bold)
                            Text("·").opacity(0.5)
                            Text(r.cost(at: ctx.date).usd)
                        }
                        .font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                    }
                }
                .padding(.horizontal, Theme.cardInset).padding(.top, 10)
            } else {
                Text("Nearest chargers").font(.headline).padding(.top, 10)   // iOS sheet title size
            }
            }
            .padding(.bottom, collapsed ? Theme.cardInset : 12)
            .contentShape(.rect)
            .onTapGesture { withAnimation(.snappy) { if collapsed { collapsed = false } else { expanded.toggle() } } }
            .gesture(DragGesture(minimumDistance: 8).onEnded { v in
                withAnimation(.snappy) {
                    if v.translation.height > 50 || v.predictedEndTranslation.height > 160 { if expanded { expanded = false } else { collapsed = true } }
                    else if v.translation.height < -30 { if collapsed { collapsed = false } else { expanded = true } }
                }
            })
            .sensoryFeedback(.selection, trigger: collapsed)
            if !collapsed {
            ScrollView {
                VStack(spacing: expanded ? 2 : 0) {
                    ForEach(expanded ? list : Array(list.filter { $0.id == picked?.id }.prefix(1))) { s in row(s) }
                    if !expanded, list.count > 1 {
                        Button { withAnimation(.snappy) { expanded = true } } label: {
                            // secondary action: grey, not another blue
                            HStack(spacing: 6) {
                                Text("\(list.count - 1) more nearby")
                                Image(systemName: "chevron.up").font(.footnote.weight(.bold))
                            }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
                        }
                        .buttonStyle(.plain)
                    }
                }.padding(.horizontal, Theme.cardInset)
            }
            .scrollDisabled(!expanded)
            .frame(maxHeight: expanded ? 420 : nil)
            .fixedSize(horizontal: false, vertical: !expanded)   // peek = exactly its content, so the gaps below stay even
            VStack(spacing: 12) {
                // payment is picked at checkout, not here
                if mode == .ret {
                    Button { showKeep = true } label: {
                        HStack(spacing: 12) {
                            AppIcon("clock", size: 22).foregroundStyle(Theme.ink)
                                .frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Need more time?").font(.headline)
                                Text("No late fee until \(model.lateFeeFrom?.shortDay ?? "")")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            AppIcon("chevron.right", size: 14).foregroundStyle(.secondary)
                        }
                        .padding(12).background(Theme.brandSoft, in: .rect(cornerRadius: Theme.optionRadius, style: .circular))
                    }
                    .buttonStyle(.plain)
                }
                if returning, let p = picked {
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Slide it into any empty slot").font(.headline)
                            Text("Billing stops the moment \(p.venue) sees it").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12).background(Theme.brandSoft, in: .rect(cornerRadius: Theme.noticeRadius, style: .circular))
                } else {
                    HStack(spacing: 10) {
                        PrimaryButton(title: goTitle, systemImage: nil) {
                            if let s = picked { model.walkTo = s }
                        }
                        .disabled(picked == nil)
                        if mode == .rent {
                            Button { model.startRentFlow(at: picked) } label: {
                                AppIcon("qrcode.viewfinder", size: 20).foregroundStyle(Theme.ink).frame(width: Theme.buttonHeight, height: Theme.buttonHeight)
                            }
                            .buttonStyle(GlassCircleStyle()).accessibilityLabel("Scan a kiosk QR")
                        } else {
                            Button {
                                guard let s = picked else { return }
                                returnGuide = s   // guided return (insert clip + live status), same as arriving by walking
                            } label: {
                                Text(picked?.isInsideVenue == true ? "At kiosk" : "I'm here").font(.headline).foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 18).frame(height: Theme.buttonHeight)
                                    .glassEffect(.regular.interactive(), in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.cardInset).padding(.bottom, Theme.cardInset)
            .padding(.top, expanded || list.count <= 1 ? 12 : 0)
            }   // !collapsed
        }
        .frame(maxWidth: .infinity)             // always full width (collapsed used to shrink to the title)
        .background(Color(uiColor: .systemGroupedBackground), in: .floatingPanel(top: Theme.sheetRadius, minimumBottom: 38))
        .shadow(color: .black.opacity(0.14), radius: 24, y: 6)
    }

    /// Point half way along the walking route (by distance).
    private var routeMidpoint: CLLocationCoordinate2D? {
        guard let poly = route?.polyline, poly.pointCount > 1 else { return nil }
        let pts = poly.points(); var total = 0.0
        for i in 1..<poly.pointCount { total += pts[i - 1].distance(to: pts[i]) }
        var half = total / 2
        for i in 1..<poly.pointCount {
            let d = pts[i - 1].distance(to: pts[i])
            if half <= d, d > 0 {
                let t = half / d
                return MKMapPoint(x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t, y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t).coordinate
            }
            half -= d
        }
        return pts[poly.pointCount - 1].coordinate
    }

    private var routeMinutes: Int? {
        route.map { max(1, Int(ceil($0.expectedTravelTime / 60))) }
    }

    private var goTitle: String {
        guard picked != nil else { return "No kiosks nearby" }
        if let routeMinutes { return "Walk · \(routeMinutes) min" }
        return routeUnavailable ? "Try directions" : "Walk"
    }

    private func row(_ s: Station) -> some View {
        let ok = usable(s)
        let count = mode == .rent ? s.chargers : s.returnSlots
        let duration = s.id == picked?.id ? routeMinutes : nil
        let estimate = duration.map { "\($0) min walk" } ?? "≈\(model.walkMinutes(s)) min walk"
        return Button { select(s) } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(s.kioskImage).resizable().scaledToFit().frame(width: 40, height: 58)
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 3)   // no tile: the 3D kiosk reads on its own
                // two aligned rows: name ↔ price on one baseline, details ↔ "/30 min" on the next
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(s.venue).font(.headline).lineLimit(1).truncationMode(.tail)
                            .foregroundStyle(ok ? .primary : .secondary)
                        Spacer(minLength: 8)
                        if ok, expanded, mode == .rent {
                            Text(s.rate.pricePerBlock.usd).font(.headline).monospacedDigit()
                        }
                    }
                    HStack(alignment: .center, spacing: 4) {
                        // one quiet line: "⚡ Faster · 2 min walk · 8 ready" (no chip background)
                        HStack(spacing: 4) {
                            if s.id == ready.first?.id {
                                AppIcon("bolt.fill", size: 13)
                                Text("Faster ·").fontWeight(.semibold)
                            }
                        }
                        .font(.subheadline).foregroundStyle(tint)
                        Text(s.status == .offline ? "Offline" : ok ? "\(estimate) · \(count) \(mode == .rent ? "ready" : "empty")" : "Full right now")
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 4)
                        if ok, mode == .rent, expanded { Text("/\(s.rate.blockLabel)").font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            // like the web: rows sit flat on the sheet; only the picked one (in the full list) gets a white card
            // peek: the one kiosk sits on a light white card (like the web); full list: only the picked row has it
            .background(!expanded || s.id == picked?.id ? Color(uiColor: .secondarySystemGroupedBackground) : .clear,
                        in: .rect(cornerRadius: Theme.rowRadius, style: .circular))
            .overlay {
                if pinFlashID == s.id {
                    RoundedRectangle(cornerRadius: Theme.rowRadius, style: .circular)
                        .fill(tint.opacity(pinFlashOpacity))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(s.id == picked?.id ? .isSelected : [])
        .disabled(!ok)
    }

    private func zoom(_ k: Double) {
        guard let c = lastCamera else { return }
        withAnimation(.smooth(duration: 0.35)) { camera = .camera(c.zoomed(k)) }
    }

    private func recenter() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) {
            camera = .camera(MapCamera(centerCoordinate: model.userLocation.coordinate,
                                       distance: lastCamera?.distance ?? 850))
        }
        if !reduceMotion { locationPulse += 1 }
    }

    private func selectPin(_ station: Station) {
        guard usable(station) else { return }
        select(station)
        guard !reduceMotion else { return }
        pinFlashID = station.id
        pinFlashOpacity = 0.15
        pinTap += 1
    }

    private func select(_ s: Station) {
        guard usable(s) else { return }
        guard s.id != picked?.id else { return }
        route = nil
        routeUnavailable = false
        pick = s.id
    }

    private func loadRoute() async {
        route = nil
        routeUnavailable = false
        guard let station = picked else { return }
        let origin = model.userLocation
        let result = await WalkDirections.route(from: origin, to: station.location)
        guard !Task.isCancelled, picked?.id == station.id else { return }
        routeReveal = reduceMotion ? 1 : 0
        route = result
        routeUnavailable = result == nil
        let size = MKMapSize(width: 1, height: 1)
        var rect = MKMapRect(origin: MKMapPoint(origin.coordinate), size: size)
        rect = rect.union(MKMapRect(origin: MKMapPoint(station.coordinate), size: size))
        if let result { rect = rect.union(result.polyline.boundingMapRect) }
        let pad = max(rect.size.width, rect.size.height, 900) * 0.55
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.8)) {
            camera = .rect(rect.insetBy(dx: -pad, dy: -pad * 1.15))
        }
        guard result != nil, !reduceMotion else { return }
        for step in 1...6 {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            let progress = Double(step) / 6
            routeReveal = 1 - (1 - progress) * (1 - progress)
        }
    }
}

struct WalkCallout: View {
    let minutes: Int
    var body: some View {
        Label("\(minutes) min", systemImage: "figure.walk")
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.regularMaterial, in: .capsule)
    }
}

struct WalkingRouteOverlay: MapContent {
    let route: MKRoute
    let origin: CLLocationCoordinate2D
    let station: Station
    var reveal = 1.0

    var body: some MapContent {
        let street = route.polyline.walkingCoordinates
        MapPolyline(coordinates: street)
            .stroke(Color.white.opacity(reveal), style: StrokeStyle(lineWidth: 2 + 7 * reveal, lineCap: .round, lineJoin: .round))
        MapPolyline(coordinates: street)
            .stroke(Theme.brand.opacity(reveal), style: StrokeStyle(lineWidth: 2 + 3 * reveal, lineCap: .round, lineJoin: .round))
        if let start = street.first,
           WalkDirections.distance(origin, start) > 2 {
            MapPolyline(coordinates: [origin, start])
                .stroke(Theme.brand.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 6]))
        }
        if let end = street.last, WalkDirections.needsHandoff(for: station, from: end) {
            Annotation("Walking route ends", coordinate: end) { RouteEndpoint() }
                .annotationTitles(.hidden)
        }
    }
}

struct RouteEndpoint: View {
    var body: some View {
        Circle().fill(.white)
            .overlay(Circle().strokeBorder(Theme.brand, lineWidth: 2))
            .frame(width: 12, height: 12)
            .accessibilityLabel("Walking route ends here")
    }
}

/// The real kiosk (Blender render) standing on the map, live count badge, soft ground shadow.
struct KioskPin: View {
    let station: Station
    var count: Int? = nil
    var tint: Color = Theme.brand
    var selected = false
    var glow = false

    var body: some View {
        let n = count ?? station.chargers
        Image(station.kioskImage).resizable().scaledToFit().frame(height: selected ? 78 : 58)
                .saturation(station.status == .offline ? 0 : 1).opacity(station.status == .offline ? 0.6 : 1)
                .shadow(color: .black.opacity(0.28), radius: 4, y: 5)
                .overlay(alignment: .topTrailing) {
                    Text(station.status == .offline ? "×" : "\(n)")
                        .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .frame(minWidth: 24, minHeight: 24).padding(.horizontal, 4)
                        .background(station.status == .offline ? Theme.offline : n > 0 ? tint : Theme.warning, in: .capsule)
                        .overlay(Capsule().stroke(.white, lineWidth: 2.5))
                        .offset(x: 12, y: -8)
                }
            .background(alignment: .bottom) {
                Ellipse().fill(selected ? tint.opacity(0.22) : .black.opacity(0.16))
                    .frame(width: selected ? 48 : 26, height: 8).blur(radius: 2)
            }
        .animation(.spring(duration: 0.3, bounce: 0.35), value: selected)
        .accessibilityLabel("\(station.venue), \(station.status == .offline ? "offline" : "\(n)")")
    }
}

struct UserDot: View {
    var pulse = 0

    var body: some View {
        ZStack {
            Circle().fill(Theme.brand.opacity(0.18)).frame(width: 44, height: 44)
            Circle().fill(Theme.brand).frame(width: 18, height: 18).overlay(Circle().stroke(.white, lineWidth: 3))
            Color.clear.frame(width: 28, height: 28)
                .keyframeAnimator(initialValue: 1.0, trigger: pulse) { _, progress in
                    Circle().strokeBorder(Theme.brand, lineWidth: 2)
                        .frame(width: 28, height: 28)
                        .scaleEffect(0.7 + 1.1 * progress)
                        .opacity(1 - progress)
                } keyframes: { _ in
                    MoveKeyframe(0.0)
                    CubicKeyframe(1.0, duration: 0.4)
                }
                .allowsHitTesting(false)
        }
    }
}

/// The real issue on return isn't a full kiosk (any empty slot works), it's being too far or too late.
struct KeepLongerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var hours = 24
    private let options: [(Int, String, String)] = [(2, "2 more hours", "Running late"), (24, "Until tomorrow", "Kiosk is far or closed now"), (48, "2 more days", "Travelling")]

    var body: some View {
        FittedActionSheet { content }
            .environment(\.colorScheme, .light)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeading(title: "Keep it longer", subtitle: "No late fee while you hold it", onClose: { dismiss() })
            ForEach(options, id: \.0) { o in
                Button { hours = o.0 } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) { Text(o.1).font(.headline); Text(o.2).font(.subheadline).foregroundStyle(.secondary) }
                        Spacer()
                        if let r = model.activeRental?.rate { Text(min(r.dailyMax, ceil(Double(o.0) * 60 / r.blockMinutes) * r.pricePerBlock).usd).font(.headline) }
                    }
                    .padding(14).background(.white, in: .rect(cornerRadius: Theme.optionRadius, style: .circular))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.optionRadius, style: .circular)
                            .strokeBorder(hours == o.0 ? Theme.ink.opacity(0.65) : .clear, lineWidth: 1.5)
                            .allowsHitTesting(false)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(hours == o.0 ? .isSelected : [])
            }
            Label("Never more than \(model.activeRental?.rate.dailyMax.usd ?? "") a day. Return to any kiosk anytime; you only pay for the time you kept it.", symbol: "lock.fill")
                .font(.footnote).foregroundStyle(.secondary)
            PrimaryButton(title: hours == 24 ? "Keep until tomorrow" : "Keep longer") {
                model.keepLonger(hours: hours); dismiss()
            }
        }
        .padding(Theme.cardInset)
    }
}

/// Return receipt as a sheet over the map (no extra screen).
struct ReturnReceiptSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let record: RentalRecord

    var body: some View {
        FittedActionSheet { content }
            .environment(\.colorScheme, .light)
            .overlay { BoltConfetti().allowsHitTesting(false).ignoresSafeArea() }
            .sensoryFeedback(.success, trigger: record.id)
    }

    private var content: some View {
        VStack(spacing: 4) {
            AppIcon("checkmark", size: 27).foregroundStyle(.white)
                .frame(width: 54, height: 54).background(Theme.success, in: .circle)
                .padding(.top, Theme.cardInset)
            Text("Charger returned").font(.headline).padding(.top, 10)
            Text(record.total.usd).font(.system(size: 44, weight: .bold, design: .rounded))
            Text("Charged to \(record.payment.title)").foregroundStyle(.secondary)
            VStack(spacing: 0) {
                line("Duration", "\(max(1, Int(record.duration / 60))) min", nil)
                line("Picked up", record.pickup.venue, record.startedAt.shortTime)
                line("Returned", record.dropoff.venue, record.endedAt.shortTime)
                line("\(record.blocks) × \(record.rate.blockLabel) at \(record.rate.pricePerBlock.usd)", record.total.usd, nil)
                line("Hold", "\(record.rate.hold.usd) released", nil, last: true)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.groupRadius, style: .circular)).padding(.top, 12)
            ShareLink(item: receiptSummary) {
                Label("Share receipt", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: Theme.buttonHeight)
            }
            PrimaryButton(title: "Done") { dismiss() }
        }
        .padding(Theme.cardInset)
    }

    private var receiptSummary: String {
        """
        chargeFUZE receipt
        Rental \(record.id)
        Picked up: \(record.pickup.venue) · \(record.startedAt.shortDay) \(record.startedAt.shortTime)
        Returned: \(record.dropoff.venue) · \(record.endedAt.shortDay) \(record.endedAt.shortTime)
        Total: \(record.total.usd)
        """
    }

    private func line(_ k: String, _ v: String, _ sub: String?, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(k).foregroundStyle(.secondary)
                Spacer(minLength: 16)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(v)
                    if let sub { Text(sub).font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            if !last { Divider().padding(.leading, 16) }
        }
    }
}
