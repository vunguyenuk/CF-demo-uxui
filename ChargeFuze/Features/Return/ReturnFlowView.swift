import SwiftUI
import PhotosUI
import MapKit

struct ReturnFlowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                switch model.returnStep {
                case .find: FindReturnStation()
                case .atStation(let s): InsertStep(station: s)
                case .verifying(let s): VerifyingStep(station: s)
                case .receipt(let r): ReceiptView(record: r)
                case .notConfirmed(let s): NotConfirmedView(station: s)
                case .claimSent(let t): ClaimSentView(ticket: t)
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if case .receipt = model.returnStep {} else if case .claimSent = model.returnStep {} else {
                        Button { model.finishReturnFlow() } label: { Label("Close", symbol: "xmark") }
                    }
                }
            }
        }
        .fullScreenCover(item: $model.directionsTo) { s in DirectionsView(station: s) }
    }
}

// MARK: - Find: the fastest station first, drawn like a maps app

struct FindReturnStation: View {
    @Environment(AppModel.self) private var model
    @State private var pickID: String?
    @State private var route: MKRoute?
    @State private var position: MapCameraPosition = .automatic
    @State private var showCantReturn = false

    private var list: [Station] { model.returnCandidates }
    private var pick: Station? { list.first { $0.id == pickID } ?? list.first }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $position) {
                UserAnnotation()
                if let route, let pick {
                    WalkingRouteOverlay(route: route, origin: model.userLocation.coordinate, station: pick)
                }
                ForEach(list) { s in
                    Annotation(s.venue, coordinate: s.coordinate) {
                        Button { select(s) } label: {
                            Text("\(s.returnSlots)").font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundStyle(s.id == pick?.id ? .white : Theme.success)
                                .frame(width: 34, height: 34)
                                .background(s.id == pick?.id ? Theme.success : .white, in: .circle)
                                .overlay(Circle().stroke(Theme.success, lineWidth: 2.5))
                                .scaleEffect(s.id == pick?.id ? 1.2 : 1)
                        }
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(maxHeight: .infinity)

            if let s = pick { sheet(s) }
        }
        .ignoresSafeArea(edges: .top)
        .task(id: pick?.id) {
            route = nil
            guard let station = pick else { return }
            let result = await WalkDirections.route(from: model.userLocation, to: station.location)
            guard !Task.isCancelled, pick?.id == station.id else { return }
            withAnimation(.smooth) {
                route = result
                if let result { position = .rect(result.polyline.boundingMapRect.insetBy(dx: -400, dy: -900)) }
                else { position = .camera(MapCamera(centerCoordinate: station.coordinate, distance: 1400)) }
            }
        }
        .sheet(isPresented: $showCantReturn) { CantReturnSheet().presentationDetents([.medium, .large]) }
    }

    private func sheet(_ s: Station) -> some View {
        let held = model.heldSlot?.stationID == s.id ? model.heldSlot : nil
        return VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(.secondary.opacity(0.35)).frame(width: 38, height: 5).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                if s.id == list.first?.id {
                    Text("Fastest").font(.footnote.weight(.bold)).foregroundStyle(Theme.success)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(Theme.success.opacity(0.12), in: .capsule)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(model.walkMinutes(s)) min").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.success)
                        .contentTransition(.numericText())
                    Text("(\(model.distanceText(s)))").font(.title3).foregroundStyle(.secondary)
                }
                Text(s.venue).font(.title3.weight(.semibold))
                Text("\(s.returnSlots) free slots · \(s.hours)").font(.subheadline).foregroundStyle(.secondary)
            }
            if let held {
                HStack(spacing: 12) {
                    IconTile(icon: "lock.fill")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Slot \(held.slot) is held for you").font(.headline)
                        Text(timerInterval: Date.now...held.until, countsDown: true).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.ink)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.brandSoft, in: .rect(cornerRadius: Theme.noticeRadius, style: .circular))
                .transition(.scale.combined(with: .opacity))
            }
            HStack(spacing: 10) {
                Button {
                    if held == nil { withAnimation(.bouncy) { model.holdSlot(at: s) } }
                    else { model.directionsTo = s }
                } label: {
                    Label(held == nil ? "Hold a slot" : "Directions", symbol: held == nil ? "lock.fill" : "figure.walk")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
                }
                .buttonStyle(FilledCapsuleStyle(tint: Theme.brand))
                Button { model.arrived(at: s) } label: { Text("I'm here").font(.headline).frame(maxWidth: .infinity, minHeight: Theme.buttonHeight) }
                    .buttonStyle(.plain)
                    .frame(minHeight: Theme.buttonHeight)
                    .padding(.horizontal, 14)
                    .background(Theme.brandSoft, in: .capsule)
            }
            Text("Other stations").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 6)
            VStack(spacing: 0) {
                ForEach(Array(list.filter { $0.id != s.id }.prefix(3).enumerated()), id: \.element.id) { i, x in
                    if i > 0 { Divider().padding(.leading, 16) }
                    Button { select(x) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(x.venue).font(.body.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
                                Text("\(x.returnSlots) free slots").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(model.walkMinutes(x)) min").fontWeight(.semibold).foregroundStyle(Theme.success)
                            AppIcon("chevron.right", size: 13).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16).frame(minHeight: 56).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: Theme.groupRadius, style: .circular))
            Button { showCantReturn = true } label: {
                HStack(spacing: 14) {
                    IconTile(icon: "person.2.fill", color: .gray)
                    Text("Can't get to a station?").foregroundStyle(.primary)
                    Spacer()
                    AppIcon("chevron.right", size: 13).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16).frame(minHeight: 56)
                .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: Theme.groupRadius, style: .circular))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
        .background(Color(uiColor: .secondarySystemBackground), in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .circular))
        .shadow(color: .black.opacity(0.08), radius: 20, y: -6)
        .animation(.smooth, value: model.heldSlot)
    }

    private func select(_ s: Station) {
        withAnimation(.smooth) { pickID = s.id }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

/// Every way out, before the deadline. Passing it on is software-only: the rental moves accounts.
struct CantReturnSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var passing = false

    var body: some View {
        NavigationStack {
            List {
                if let r = model.activeRental {
                    Section {
                        Button { passing = true } label: {
                            option("person.2.fill", Theme.brand, "Pass it to a friend", "They hold their phone to yours or open your link. The rental moves to their account and your billing stops.")
                        }
                        .buttonStyle(.plain)
                        option("clock.fill", Theme.warning, "Return it later", "You have until \(r.nonReturnAt.shortDay), \(r.nonReturnAt.shortTime). Never more than \(r.rate.dailyMax.usd) a day, and we'll remind you first.")
                        option("mappin.and.ellipse", Theme.success, "Any station works", "\(model.returnCandidates.count) stations have free slots right now.")
                    }
                }
            }
            .navigationTitle("Can't get to a station?")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $passing) { PassItOnView { dismiss() } }
        }
    }

    private func option(_ icon: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct PassItOnView: View {
    @Environment(AppModel.self) private var model
    var onDone: () -> Void
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            AppIcon("wave.3.right", size: 54).foregroundStyle(Theme.brand)
                .frame(width: 120, height: 120)
                .background(Theme.brandSoft, in: .circle)
                .scaleEffect(pulse ? 1.06 : 0.96)
                .onAppear { withAnimation(.easeInOut(duration: 1).repeatForever()) { pulse = true } }
            Text("Hold your phones together").font(.title.bold())
            Text("Or share the link. When your friend accepts, the charger and the rest of the rental move to their account.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 24)
            if let id = model.activeRental?.id {
                ShareLink(item: URL(string: "https://chargefuze.com/pass/\(id)")!) {
                    Text("chargefuze.com/pass/\(id)").font(.callout.monospaced())
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: Theme.fieldRadius, style: .circular))
                }
            }
            Spacer()
            PrimaryButton(title: "Demo: friend accepted", systemImage: "checkmark") {
                onDone()
                model.passRental(to: "Minh")
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
    }
}

// MARK: - Insert: the Blender clip of a charger going back into its slot

struct InsertStep: View {
    @Environment(AppModel.self) private var model
    let station: Station

    var body: some View {
        let held = model.heldSlot?.stationID == station.id ? model.heldSlot : nil
        ZStack(alignment: .bottom) {
            LoopingVideoView(name: "insert").ignoresSafeArea()
            LinearGradient(stops: [.init(color: .white.opacity(0), location: 0), .init(color: .white, location: 0.42)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 420).ignoresSafeArea(edges: .bottom).allowsHitTesting(false)
            VStack(spacing: 10) {
                Text(held.map { "Slot \($0.slot)" } ?? "Any empty slot")
                    .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6).background(Theme.brand, in: .capsule)
                    .phaseAnimator([1.0, 1.08]) { v, s in v.scaleEffect(s) } animation: { _ in .easeInOut(duration: 0.7) }
                Text("Push it in until it clicks").font(.system(size: 32, weight: .bold))
                Text(held == nil ? "Cables first. The slot light turns blue." : "Cables first. The held slot is flashing blue.")
                    .foregroundStyle(.secondary)
                PrimaryButton(title: "I put it back", systemImage: "checkmark") { model.insertedCharger(at: station) }
                    .padding(.top, 8)
                Text("Tapping stops billing right away, even if the kiosk is slow.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .floatingAtBottom(Theme.cardInset)
        }
        .navigationTitle(station.venue).navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Proof of return: kiosk, Bluetooth and GPS checked while the clock is already frozen

struct VerifyingStep: View {
    @Environment(AppModel.self) private var model
    let station: Station
    enum Check { case waiting, ok(String), warn(String) }
    @State private var kiosk: Check = .waiting
    @State private var bluetooth: Check = .waiting
    @State private var gps: Check = .waiting
    @State private var needsSlotScan = false
    @State private var scanning = false
    @State private var slot = Int.random(in: 1...24)

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    AppIcon("snowflake", size: 30).foregroundStyle(Theme.brand)
                        .frame(width: 76, height: 76).background(Theme.brandSoft, in: .circle)
                    Text("Billing stopped at").font(.body).foregroundStyle(.secondary)
                    Text(model.returnStoppedAt.shortTime).bigNumber(54)
                }
                .padding(.top, 30)

                VStack(spacing: 0) {
                    checkRow(kiosk, "Kiosk confirms slot \(slot)", "Asking \(station.id)…")
                    Divider().padding(.leading, 42)
                    checkRow(bluetooth, "Your phone is next to the kiosk", "Bluetooth")
                    Divider().padding(.leading, 42)
                    checkRow(gps, "Location matches \(station.venue)", "GPS")
                }
                .padding(.horizontal, 16)
                .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: Theme.groupRadius, style: .circular))

                if needsSlotScan {
                    VStack(spacing: 12) {
                        Text("Your phone's proof is enough. Scan the small QR on slot \(slot) to finish. You won't be charged while we check.")
                            .font(.body).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16).background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: Theme.cardRadius, style: .circular))
                        PrimaryButton(title: scanning ? "Checking…" : "Scan slot \(slot)", systemImage: "qrcode.viewfinder") { scanSlot() }
                            .disabled(scanning)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
        }
        .navigationBarBackButtonHidden()
        .task { await run() }
        .sensoryFeedback(.success, trigger: needsSlotScan)
    }

    private func checkRow(_ c: Check, _ title: String, _ waiting: String) -> some View {
        HStack(spacing: 14) {
            switch c {
            case .waiting: ProgressView().frame(width: 26, height: 26)
            case .ok: AppIcon("checkmark", size: 14).foregroundStyle(.white).frame(width: 26, height: 26).background(Theme.success, in: .circle).transition(.scale)
            case .warn: Text("!").font(.headline.bold()).foregroundStyle(.white).frame(width: 26, height: 26).background(Theme.warning, in: .circle).transition(.scale)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text({ switch c { case .waiting: waiting; case .ok(let t), .warn(let t): t } }()).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    private func run() async {
        if let h = model.heldSlot, h.stationID == station.id { slot = h.slot }
        do {
            try await Task.sleep(for: .milliseconds(900))
            withAnimation(.bouncy) { bluetooth = .ok("0.4 m away") }
            try await Task.sleep(for: .milliseconds(500))
            withAnimation(.bouncy) { gps = .ok("\(Int(model.distance(to: station))) m from the kiosk") }
            try await Task.sleep(for: .milliseconds(model.demoReturnNotConfirmed ? 1200 : 700))
            if model.demoReturnNotConfirmed {
                withAnimation(.bouncy) { kiosk = .warn("The kiosk is offline right now"); needsSlotScan = true }
            } else {
                withAnimation(.bouncy) { kiosk = .ok("Charger detected · \(model.returnStoppedAt.shortTime)") }
                try await Task.sleep(for: .milliseconds(700))
                model.lastReturnByProof = false
                model.completeReturn(at: station, slot: slot, endedAt: model.returnStoppedAt)
            }
        } catch { return }
    }

    private func scanSlot() {
        guard let rentalID = model.activeRental?.id else { return }
        scanning = true
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            guard isVerifying(rentalID: rentalID) else { return }
            withAnimation(.bouncy) { kiosk = .ok("Slot \(slot) scanned · good standing, closed instantly") }
            try? await Task.sleep(for: .milliseconds(900))
            guard isVerifying(rentalID: rentalID) else { return }
            model.lastReturnByProof = true
            model.completeReturn(at: station, slot: slot, endedAt: model.returnStoppedAt)
        }
    }

    private func isVerifying(rentalID: String) -> Bool {
        guard model.showReturnFlow, model.activeRental?.id == rentalID,
              case .verifying(let current) = model.returnStep else { return false }
        return current.id == station.id
    }

}

// MARK: - Receipt (S1: the proof of return)

struct ReceiptView: View {
    @Environment(AppModel.self) private var model
    let record: RentalRecord
    @State private var shownTotal: Double = 0
    @State private var checkIn = false

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 16) {
                    AppIcon("checkmark", size: 40).foregroundStyle(.white)
                        .frame(width: 60, height: 60).background(Theme.success, in: .circle)
                        .scaleEffect(checkIn ? 1 : 0.3).opacity(checkIn ? 1 : 0)
                        .padding(.top, 12)
                    Text(model.lastReturnNote ?? "Charger returned").font(.headline).accessibilityAddTraits(.isHeader)
                    Text(shownTotal.usd).font(.largeTitle.bold().monospacedDigit())
                        .contentTransition(.numericText(value: shownTotal))
                    Label(model.lastReturnNote != nil ? "Billing stopped · \(record.endedAt.shortTime)"
                          : model.lastReturnByProof ? "Confirmed by your phone's proof · \(record.endedAt.shortTime)"
                          : "Confirmed by the kiosk · \(record.endedAt.shortTime)",
                          symbol: model.lastReturnByProof ? "wave.3.right" : "checkmark")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.success)
                        .padding(.horizontal, 14).padding(.vertical, 8).background(Theme.success.opacity(0.1), in: .capsule)

                    VStack(spacing: 0) {
                        if record.returnSlot > 0 {
                            row("Station", record.dropoff.venue); Divider(); row("Slot", "\(record.returnSlot)"); Divider()
                        }
                        row("Time", record.duration.friendly); Divider()
                        row("\(record.blocks) × \(record.rate.headline)", record.total.usd); Divider()
                        row("Paid with", record.payment.title)
                    }
                    .padding(.horizontal, 16)
                    .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: Theme.groupRadius, style: .circular))

                    HoldTimeline(amount: record.rate.hold, released: true, rentalID: record.id)

                    Button {
                        model.finishReturnFlow()
                        Task { try? await Task.sleep(for: .milliseconds(350)); model.showHelp = true }
                    } label: {
                        Label("Get help", symbol: "questionmark.circle")
                            .font(.subheadline.weight(.semibold)).frame(minHeight: Theme.buttonHeight)
                    }
                    PrimaryButton(title: "Done") { model.finishReturnFlow() }
                }
                .padding(Theme.cardInset)
            }
            BoltConfetti().allowsHitTesting(false).ignoresSafeArea()
        }
        .navigationBarBackButtonHidden()
        .sensoryFeedback(.success, trigger: checkIn)
        .task {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { checkIn = true }
            for i in 1...24 {
                try? await Task.sleep(for: .milliseconds(35))
                withAnimation(.snappy) { shownTotal = record.total * Double(i) / 24 }
            }
        }
    }

    private func row(_ l: String, _ v: String) -> some View {
        HStack { Text(l).foregroundStyle(.secondary); Spacer(); Text(v).fontWeight(.semibold).multilineTextAlignment(.trailing) }
            .font(.body).frame(minHeight: Theme.buttonHeight)
    }
}

/// Placed → Released → Off the statement: the three moments people ask about.
struct HoldTimeline: View {
    let amount: Double
    let released: Bool
    let rentalID: String
    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your \(amount.usd) hold", symbol: "lock.open.fill").font(.headline)
            HStack(alignment: .top, spacing: 0) {
                node(0, "Placed", "at pickup")
                bar(1)
                node(1, "Released", "just now")
                bar(2)
                node(2, "Off your statement", "bank, ≤ 5 days")
            }
            Text("Shows as FUZE TECHNOLOGY · Rental \(rentalID)").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: Theme.groupRadius, style: .circular))
        .task { for i in 1...(released ? 2 : 1) { try? await Task.sleep(for: .milliseconds(450)); withAnimation(.bouncy) { step = i } } }
    }

    private func node(_ i: Int, _ t: String, _ s: String) -> some View {
        VStack(spacing: 4) {
            Circle().fill(i < step ? Theme.success : Color(uiColor: .systemGray4)).frame(width: 16, height: 16)
            Text(t).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
            Text(s).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    private func bar(_ i: Int) -> some View {
        Capsule().fill(i < step ? Theme.success : Color(uiColor: .systemGray4)).frame(height: 3).frame(maxWidth: 30).padding(.top, 6.5)
    }
}

// MARK: - S2: returned, but the kiosk didn't confirm

struct NotConfirmedView: View {
    @Environment(AppModel.self) private var model
    let station: Station
    @State private var slot = 1
    @State private var photoItem: PhotosPickerItem?
    @State private var hasPhoto = false
    private let returnedAt = Date.now

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("The kiosk hasn't confirmed yet", symbol: "exclamationmark.triangle.fill")
                        .font(.headline).foregroundStyle(Theme.warning)
                    Text("Don't worry. We're keeping **\(returnedAt.shortTime)** as your return time. Add two details and we'll match it with the kiosk log. You won't be charged a non-return fee while we check.")
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
            Section("Which slot did you use?") {
                Stepper("Slot \(slot)", value: $slot, in: 1...24)
                SlotGrid(highlight: slot).frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
            Section("Photo of the charger in the slot (optional)") {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(hasPhoto ? "Photo added" : "Add a photo", symbol: hasPhoto ? "checkmark.circle.fill" : "camera.fill")
                }
                .onChange(of: photoItem) { _, item in hasPhoto = item != nil }
            }
            Section {
                InfoRow(label: "Station", value: station.venue)
                InfoRow(label: "Your location", value: "At the kiosk (\(Int(model.distance(to: station))) m)")
                InfoRow(label: "Time", value: returnedAt.shortTime)
            } footer: {
                Text("These are attached automatically.")
            }
            Section {
                Button {
                    model.submitReturnClaim(station: station, slot: slot, hasPhoto: hasPhoto)
                } label: {
                    Text("Send proof of return").font(.headline).frame(maxWidth: .infinity).frame(height: Theme.buttonHeight)
                }
                .buttonStyle(FilledCapsuleStyle(tint: Theme.brand))
                .listRowBackground(Color.clear)
                Button("Try the kiosk again") { model.insertedCharger(at: station) }
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Return not confirmed")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.warning, trigger: station.id)
    }
}

struct ClaimSentView: View {
    @Environment(AppModel.self) private var model
    let ticket: SupportTicket

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            AppIcon("checkmark.seal.fill", size: 64).foregroundStyle(Theme.brand)
                .symbolEffect(.bounce, value: ticket.id)
            Text("Proof of return sent").font(.title2.bold())
            Text(ticket.note).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 30)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ticket.evidence, id: \.self) { e in
                    Label(e, symbol: "checkmark.circle.fill").font(.subheadline)
                        .foregroundStyle(.primary).symbolRenderingMode(.multicolor)
                }
                Text("Case \(ticket.id) · see it any time in Help").font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
            .padding(.horizontal, 20)
            Spacer()
            PrimaryButton(title: "Done") { model.finishReturnFlow() }.padding(.horizontal, 20).padding(.bottom, 12)
        }
        .navigationBarBackButtonHidden()
    }
}
