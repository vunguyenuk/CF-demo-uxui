import SwiftUI
import MapKit

/// "Directions" opens this instead of Apple Maps: a 3D walking route with a Map / Live view switch,
/// the next turn on top and the ETA at the bottom (like a delivery-tracking screen).
struct DirectionsView: View {
    let station: Station
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable { case map = "Map", live = "Live view"; var id: Self { self } }
    @State private var mode: Mode = .map
    @State private var directions: MKRoute?
    @State private var routeUnavailable = false
    private var route: [CLLocationCoordinate2D] { directions?.polyline.walkingCoordinates ?? [] }
    @State private var steps: [(String, CLLocationDistance)] = []
    @State private var eta: TimeInterval = 0
    @State private var distance: CLLocationDistance = 0
    @State private var position: MapCameraPosition = .automatic
    @State private var progress: Double = 0          // 0...1 along the route (preview walk)
    @State private var me: CLLocationCoordinate2D?

    var body: some View {
        ZStack {
            Map(position: $position, interactionModes: mode == .map ? .all : []) {
                if let directions {
                    WalkingRouteOverlay(route: directions, origin: model.userLocation.coordinate, station: station)
                }
                Annotation(station.venue, coordinate: station.coordinate, anchor: .bottom) {
                    KioskBeacon()
                }
                Annotation("You", coordinate: me ?? model.userLocation.coordinate) { YouDot(heading: mode == .live) }
                    .annotationTitles(.hidden)
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControls { }
            .ignoresSafeArea()

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button { dismiss() } label: { AppIcon("xmark", size: 16).frame(width: 44, height: 44) }
                        .buttonStyle(GlassCircleStyle())
                    Spacer(minLength: 0)
                    Picker("View", selection: $mode.animation(.smooth(duration: 0.8))) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).frame(width: 220)
                }

                if let step = currentStep {
                    HStack(spacing: 14) {
                        AppIcon(step.icon, size: 26)
                            .font(.title2.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Theme.ink, in: .rect(cornerRadius: Theme.fieldRadius, style: .circular))
                            .contentTransition(.symbolEffect(.replace))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.text).font(.title3.weight(.semibold)).lineLimit(2)
                            Text("\(step.dist) · to \(station.venue)").font(.subheadline).foregroundStyle(.secondary)
                                .lineLimit(1).contentTransition(.numericText())
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: Theme.turnCardRadius, style: .circular))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                bottomSheet
            }
            .padding(.horizontal, 16)
        }
        .task { await loadRoute() }
        .task(id: mode) { await runCamera() }
        .sensoryFeedback(.selection, trigger: mode)
    }

    // MARK: Bottom ETA sheet
    private var bottomSheet: some View {
        VStack(spacing: 12) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 40, height: 5)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    if directions != nil {
                        Text("\(max(1, Int(ceil((eta * (1 - progress)) / 60)))) min")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text(Measurement(value: distance * (1 - progress), unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text(routeUnavailable ? "Route unavailable" : "Finding a walking route…").font(.headline)
                    }
                    Text(station.kioskLocation).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.activeRental == nil ? "Scan to rent" : "Return here") {
                    dismiss()
                    if model.activeRental != nil { model.startReturnFlow() } else { model.startRentFlow(at: station) }
                }
                .buttonStyle(FilledCapsuleStyle(tint: Theme.brand))
            }
        }
        .padding(Theme.cardInset)
        .background(.regularMaterial, in: .floatingPanel(top: Theme.walkCardRadius, minimumBottom: Theme.walkCardRadius))
        .floatingAtBottom()
    }

    // MARK: Route
    private struct Step { let icon: String; let text: String; let dist: String }
    private var currentStep: Step? {
        guard !steps.isEmpty else { return nil }
        let walked = distance * progress
        var acc: CLLocationDistance = 0
        for (i, s) in steps.enumerated() {
            acc += s.1
            if walked < acc || i == steps.count - 1 {
                let left = max(0, acc - walked)
                let icon = s.0.localizedCaseInsensitiveContains("left") ? "arrow.turn.up.left"
                    : s.0.localizedCaseInsensitiveContains("right") ? "arrow.turn.up.right"
                    : s.0.localizedCaseInsensitiveContains("arrive") || i == steps.count - 1 ? "mappin.and.ellipse" : "arrow.up"
                return Step(icon: icon, text: s.0, dist: Measurement(value: left, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))
            }
        }
        return nil
    }

    private func loadRoute() async {
        let result = await WalkDirections.route(from: model.userLocation, to: station.location)
        guard !Task.isCancelled else { return }
        if let result {
            directions = result
            steps = result.steps.filter { !$0.instructions.isEmpty }.map { ($0.instructions, $0.distance) }
            eta = result.expectedTravelTime
            distance = result.distance
        } else {
            routeUnavailable = true
        }
        withAnimation(.smooth(duration: 1.2)) { position = overview }
    }

    private var overview: MapCameraPosition {
        let mid = route.isEmpty ? station.coordinate : route[route.count / 2]
        return .camera(MapCamera(centerCoordinate: mid, distance: max(600, distance * 2.4), heading: 20, pitch: 60))
    }

    /// Map: tilted overview. Live view: the camera rides just behind "you", looking down the street.
    private func runCamera() async {
        if mode == .map { withAnimation(.smooth(duration: 1.0)) { position = overview } }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(33))
            guard route.count > 1 else { continue }
            progress = min(0.97, progress + 0.033 / max(30, eta / 6))   // preview walk, ~6x speed
            let p = point(at: progress), ahead = point(at: min(1, progress + 0.04))
            me = p
            if mode == .live {
                position = .camera(MapCamera(centerCoordinate: p, distance: 160, heading: bearing(p, ahead), pitch: 78))
            }
        }
    }

    private func point(at t: Double) -> CLLocationCoordinate2D {
        let locs = route.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        let segs = zip(locs, locs.dropFirst()).map { $0.distance(from: $1) }
        var target = segs.reduce(0, +) * t
        for (i, d) in segs.enumerated() {
            if target <= d || i == segs.count - 1 {
                let f = d > 0 ? min(1, target / d) : 0
                let a = route[i], b = route[i + 1]
                return .init(latitude: a.latitude + (b.latitude - a.latitude) * f, longitude: a.longitude + (b.longitude - a.longitude) * f)
            }
            target -= d
        }
        return route.last!
    }

    private func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDirection {
        let φ1 = a.latitude * .pi / 180, φ2 = b.latitude * .pi / 180, Δλ = (b.longitude - a.longitude) * .pi / 180
        let y = sin(Δλ) * cos(φ2), x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

private struct KioskBeacon: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(Theme.brand.opacity(0.25)).frame(width: 64, height: 64)
                .scaleEffect(pulse ? 1.3 : 0.6).opacity(pulse ? 0 : 1)
            Image(systemName: "bolt.fill").font(.headline).foregroundStyle(.white)
                .frame(width: 40, height: 40).background(Theme.brand, in: .circle)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: Theme.brand.opacity(0.5), radius: 8, y: 3)
        }
        .onAppear { withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true } }
    }
}

private struct YouDot: View {
    var heading: Bool
    var body: some View {
        ZStack {
            Circle().fill(Theme.brand.opacity(0.18)).frame(width: 44, height: 44)
            Circle().fill(.white).frame(width: 22, height: 22).shadow(radius: 3)
            Circle().fill(Theme.brand).frame(width: 15, height: 15)
        }
    }
}
