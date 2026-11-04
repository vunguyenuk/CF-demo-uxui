import SwiftUI

struct HomeContainer: View {
    @Environment(AppModel.self) private var model

    /// No tab bar and no search: the app opens on the nearest kiosks. Account is a button on the map.
    var body: some View {
        @Bindable var model = model
        Group {
            if model.activeRental == nil { NearbyHomeView(mode: .rent) }
            else if model.returnMode { NearbyHomeView(mode: .ret) }
            else {
                RentalMapView()
                    .safeAreaInset(edge: .bottom) {
                        RentalAccessory().frame(height: 64)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .floatingAtBottom(16)
                    }
            }
        }
        .sheet(isPresented: $model.showAccount) { AccountView() }
        .sheet(item: $model.receiptSheet) { rec in
            ReturnReceiptSheet(record: rec).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $model.showPaySheet) {
            if let s = model.rentStation { CheckoutFlow(station: s, mode: .rent) { model.pay() } }
        }
        // The assistant takes the whole screen: no tab bar competing with the chat and voice
        .fullScreenCover(isPresented: $model.showHelp) { HelpView() }
        .fullScreenCover(item: $model.quickRentStation) { s in QuickRentView(station: s) }
        .fullScreenCover(isPresented: $model.showSwap) { SwapView() }
        .sheet(isPresented: $model.showSwapReasons, onDismiss: {
            model.swapAuto = false
            model.swapChargingIssue = false
        }) { SwapReasonSheet() }
        .task(id: model.activeRental?.id) { await model.watchCharging() }
        .fullScreenCover(isPresented: $model.showRentFlow, onDismiss: model.rentFlowDidDismiss) { RentFlowView() }
        .fullScreenCover(isPresented: $model.showReturnFlow) { ReturnFlowView() }
        // Walking directions are a plain 2D map now (the 3D scene is gone)
        .fullScreenCover(item: $model.directionsTo) { s in WalkView(station: s) }
        .fullScreenCover(item: $model.walkTo, onDismiss: {
            model.swapOnArrival = false
            model.swapWalkOrigin = nil
        }) { s in WalkView(station: s, origin: model.swapWalkOrigin) }
        .sheet(isPresented: $model.showRentalSheet) {
            ActiveRentalSheet()   // detents live inside the sheet (it toggles them from "Details")
        }
    }
}

/// Bottom accessory: a live timer + cost while renting.
struct RentalAccessory: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let rental = model.activeRental {
            HStack(spacing: 12) {
                Button { model.showRentalSheet = true } label: {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        HStack(spacing: 12) {
                            AppIcon("bolt.fill", size: 16).foregroundStyle(.white)
                                .frame(width: 36, height: 36).background(Theme.success, in: .circle)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rental.station.venue).font(.headline).lineLimit(1)
                                Text("\(rental.elapsed(at: ctx.date).clock) · \(rental.cost(at: ctx.date).usd) so far")
                                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                                    .contentTransition(.numericText())
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }
                }
                .buttonStyle(.plain)
                // Match the height of the other primary actions.
                Button("Return") { model.startReturnFlow() }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: Theme.buttonHeight).background(Theme.success, in: .capsule)
                    .buttonStyle(.plain)
            }
            .padding(.leading, 12).padding(.trailing, 12)
            .accessibilityHint("Shows time, cost and return options")
        } else {
            Button { model.startRentFlow() } label: {
                HStack(spacing: 10) {
                    AppIcon("qrcode.viewfinder", size: 18)
                    Text("Scan to rent a charger").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(model.chargersNearby) nearby").font(.footnote).foregroundStyle(.secondary)
                }
                .foregroundStyle(Theme.brand)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
        }
    }
}
