import SwiftUI
import MapKit

struct RentalMapView: View {
    @Environment(AppModel.self) private var model
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: MockData.userLocation.coordinate, latitudinalMeters: 900, longitudinalMeters: 900))
    @State private var showList = false
    @State private var lastCamera: MapCamera?
    @State private var bannerDismissed = false
    @State private var nextChargeBanner = false
    @State private var warnedBlock = -1          // one "next charge" banner per billing block
    @State private var pinRoute: MKRoute?

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .top) {
            Map(position: $camera, selection: $model.selectedStationID) {
                // Demo user puck (Pershing Square)
                Annotation("You", coordinate: model.userLocation.coordinate) {
                    ZStack {
                        Circle().fill(Theme.brand.opacity(0.18)).frame(width: 44, height: 44)
                        Circle().fill(Theme.brand).frame(width: 16, height: 16).overlay(Circle().stroke(.white, lineWidth: 3))
                    }
                }
                if let pinRoute, let station = model.selectedStation {
                    WalkingRouteOverlay(route: pinRoute, origin: model.userLocation.coordinate, station: station)
                }
                ForEach(model.nearbyStations) { s in
                    Annotation(s.venue, coordinate: s.coordinate, anchor: .bottom) {
                        KioskPin(station: s, count: model.activeRental == nil ? s.chargers : s.returnSlots,
                                 tint: model.activeRental == nil ? Theme.brand : Theme.success,
                                 selected: model.selectedStationID == s.id)
                    }
                    .tag(s.id)
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { lastCamera = $0.camera }
            .mapControls { MapCompass() }
            .ignoresSafeArea(edges: .top)
            .task(id: model.selectedStationID) {
                pinRoute = nil
                guard let station = model.selectedStation else { return }
                withAnimation(.smooth(duration: 0.9)) {
                    camera = .camera(MapCamera(centerCoordinate: station.coordinate, distance: 650, heading: 0, pitch: 55))
                }
                let route = await WalkDirections.route(from: model.userLocation, to: station.location)
                guard !Task.isCancelled, model.selectedStationID == station.id else { return }
                pinRoute = route
            }

            VStack(spacing: 10) {
                topBar
                if model.notChargingBanner {
                    TopBanner(icon: "powerplug.fill", tint: Theme.warning, title: "Not charging?",
                              message: "Your iPhone hasn't charged for 2 min. Tap to swap the charger.") {
                        withAnimation(.smooth) { model.notChargingBanner = false }
                        model.showSwapReasons = true
                    }
                } else if nextChargeBanner, let r = model.activeRental {
                    TopBanner(icon: "clock.fill", tint: Theme.warning, title: "Next \(r.rate.pricePerBlock.usd) starts soon",
                              message: "Return in the next 5 min to stay at \(r.cost().usd).") {
                        withAnimation(.smooth) { nextChargeBanner = false }
                        model.startReturnFlow()
                    }
                }
            }
            .padding(.horizontal, 16)
            .animation(.smooth(duration: 0.35), value: model.notChargingBanner)
            .animation(.smooth(duration: 0.35), value: nextChargeBanner)
            .sensoryFeedback(.warning, trigger: model.notChargingBanner)
            // web: "Next $1.00 starts in 5 min. Return now to save." — once per billing block, hides after 7 s
            .task {
                while !Task.isCancelled {
                    if let r = model.activeRental, let next = r.nextChargeIn() {
                        let block = Int(r.elapsed() / (r.rate.blockMinutes * 60))
                        if next < 300, block != warnedBlock {
                            warnedBlock = block; nextChargeBanner = true
                            Task { try? await Task.sleep(for: .seconds(7)); nextChargeBanner = false }
                        }
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            .task(id: model.notChargingBanner) {
                guard model.notChargingBanner else { return }
                try? await Task.sleep(for: .seconds(10)); model.notChargingBanner = false
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // zoom + my location — problems get visual fix guides, not a chat button on the map
            VStack(spacing: 10) {
            MapZoomControl(zoomIn: { zoom(0.6) }, zoomOut: { zoom(1.6) })
            VStack(spacing: 0) {
                Button {
                    withAnimation(.smooth(duration: 0.8)) {
                        camera = .region(MKCoordinateRegion(center: model.userLocation.coordinate, latitudinalMeters: 900, longitudinalMeters: 900))
                    }
                } label: {
                    AppIcon("location.fill", size: 18).foregroundStyle(Theme.brand).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Show my location")
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(.trailing, 16).padding(.bottom, 16)
        }
        .sheet(item: Binding(get: { model.selectedStation }, set: { model.selectedStation = $0 })) { s in
            StationSheet(station: s)
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showList) {
            NearestStationSheet { s in
                showList = false
                Task { try? await Task.sleep(for: .seconds(0.35)); model.directionsTo = s }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // No search: the nearest kiosks are already on screen. Just the account button.
    private var topBar: some View {
        HStack {
            Button { model.showAccount = true } label: { AppIcon("person.fill", size: 21).frame(width: 44, height: 44) }
                .buttonStyle(GlassCircleStyle()).accessibilityLabel("Account")
            Spacer()
        }
        .padding(.top, 6)
    }

    private func zoom(_ k: Double) {
        guard let c = lastCamera else { return }
        withAnimation(.smooth(duration: 0.35)) { camera = .camera(c.zoomed(k)) }
    }
}

