import SwiftUI

/// Phone at 30%: no scanning, no browsing. Pay with the saved card, get a code, type it on the kiosk.
struct QuickRentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let station: Station
    @State private var showCheckout = false
    @State private var slot = [3, 5, 9].randomElement()!

    var body: some View {
        NavigationStack {
            Group {
                if let code = model.unlockCode(for: station) { codeView(code) } else { confirmView }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
            .navigationTitle(station.venue).navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCheckout) {
                CheckoutFlow(station: station, mode: .code, pickupMinutes: model.walkMinutes(station)) {
                    model.buyUnlockCode(at: station)
                    showCheckout = false
                }
            }
        }
    }

    private var confirmView: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image("KioskHero").resizable().scaledToFit().frame(height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(station.venue).font(.headline)
                        Text(station.kioskLocation).font(.subheadline).foregroundStyle(.secondary)
                        Text("\(model.walkMinutes(station)) min walk · \(station.chargers) chargers")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                LabeledContent("Price", value: "\(station.rate.pricePerBlock.usd) / \(station.rate.blockLabel)")
                LabeledContent("Pay with", value: model.defaultPayment.title)
            } footer: {
                Label("\(station.rate.hold.usd) hold, released when you return.", symbol: "lock.fill")
            }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Pay & get code", systemImage: "bolt.fill") { showCheckout = true }
                .floatingAtBottom(Theme.cardInset)
        }
    }

    private func codeView(_ code: String) -> some View {
        ZStack(alignment: .bottom) {
            RadialGradient(colors: [.white, Color(red: 0.87, green: 0.9, blue: 0.93)], center: .init(x: 0.5, y: 0.3), startRadius: 20, endRadius: 600)
                .ignoresSafeArea()
            // Top 88% of the kiosk render: the screen plus the first row of slots
            VStack {
                KioskKeypad(code: code, slot: slot)
                    .frame(width: 270)
                    .frame(width: 270, height: 478, alignment: .top).clipped()
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.cardRadius, topTrailingRadius: Theme.cardRadius, style: .circular))
                    .shadow(color: Color(red: 0.08, green: 0.16, blue: 0.31).opacity(0.18), radius: 18, y: 12)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            }
            codeSheet(code)
        }
    }

    private func codeSheet(_ code: String) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock code").font(.headline).accessibilityAddTraits(.isHeader)
                    Text("Type it on the kiosk screen").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = max(0, Int(model.unlockCodeExpires?.timeIntervalSince(ctx.date) ?? 0))
                    Label(String(format: "%d:%02d", left / 60, left % 60), symbol: "clock.fill")
                        .font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(Theme.brandSoft, in: .capsule)
                }
            }
            UnlockCodeDigits(code: code)
            // No confirm button: the phone may already be off. The kiosk reports the code; the app follows.
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Waiting for the kiosk").font(.headline)
                    Text("Double-tap the kiosk screen, then enter the code.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12).background(Theme.brandSoft, in: .rect(cornerRadius: Theme.noticeRadius, style: .circular))
            .task {
                guard model.isDemo else { return }
                do { try await Task.sleep(for: .seconds(9)) } catch { return }
                guard model.unlockCode(for: station) == code else { return }
                dismiss()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    model.redeemDemoUnlockCode(at: station)
                }
            }
            Label("Paid with \(model.defaultPayment.title)", symbol: "creditcard.fill").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(Theme.cardInset)
        .background(.regularMaterial, in: .floatingPanel(top: Theme.kioskCodeSheetRadius, minimumBottom: Theme.walkCardRadius))
        .floatingAtBottom()
    }


}

/// The real kiosk (Blender render): taps on its screen open the "Enter your code" popup, the code is typed, the slot is named.
struct KioskKeypad: View {
    let code: String
    let slot: Int
    @State private var open = false
    @State private var typed = 0
    @State private var pressed: String?
    @State private var done = false
    @State private var tap: CGPoint?

    // Screen rectangle inside kiosk_front.png (fractions of the image), from the Blender camera
    private let scr = CGRect(x: 0.109, y: 0.047, width: 0.782, height: 0.701)

    var body: some View {
        Image("KioskFront").resizable().scaledToFit()
            .overlay {
                GeometryReader { g in
                    let r = CGRect(x: scr.minX * g.size.width, y: scr.minY * g.size.height, width: scr.width * g.size.width, height: scr.height * g.size.height)
                    ZStack {
                        Color.black.opacity(open ? 0.4 : 0)
                        if open { popup.padding(.horizontal, r.width * 0.07).transition(.scale(scale: 0.92).combined(with: .opacity)) }
                        if let tap {
                            Circle().fill(.white.opacity(0.55)).overlay(Circle().stroke(.white, lineWidth: 2))
                                .frame(width: 30, height: 30).position(x: tap.x * r.width, y: tap.y * r.height)
                                .transition(.scale(scale: 1.6).combined(with: .opacity))
                        }
                    }
                    .frame(width: r.width, height: r.height).clipped()
                    .offset(x: r.minX, y: r.minY)
                }
            }
            .task { await run() }
            .sensoryFeedback(.selection, trigger: typed)
    }

    private var popup: some View {
        VStack(spacing: 10) {
            VStack(spacing: 1) {
                Text("Enter your code").font(.headline)
                Text("From the chargeFUZE app").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                ForEach(0..<4, id: \.self) { i in
                    Text(i < typed ? String(Array(code)[i]) : "").font(.system(.title3, design: .rounded).bold())
                        .frame(width: 34, height: 42)
                        .background(Color(red: 0.93, green: 0.95, blue: 0.97), in: .rect(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(i < typed ? Theme.brand : Color(white: 0.85), lineWidth: 1.5))
                }
            }
            if done {
                Label("Take the charger that popped out", symbol: "checkmark").font(.footnote.bold()).foregroundStyle(Theme.success)
                    .padding(10).frame(maxWidth: .infinity).background(Theme.success.opacity(0.12), in: .rect(cornerRadius: 10))
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(["1","2","3","4","5","6","7","8","9","","0","✓"], id: \.self) { k in
                        Text(k).font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 32)
                            .background(k.isEmpty ? .clear : (pressed == k || k == "✓" ? Theme.brand : Color(red: 0.94, green: 0.96, blue: 0.98)), in: .rect(cornerRadius: 8))
                            .foregroundStyle(pressed == k || k == "✓" ? .white : .primary)
                    }
                }
            }
        }
        .padding(12)
        .background(.white, in: .rect(cornerRadius: Theme.fieldRadius, style: .circular))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
    }

    private func run() async {
        while !Task.isCancelled {
            withAnimation { open = false; done = false; typed = 0 }
            try? await Task.sleep(for: .milliseconds(700))
            for p in [CGPoint(x: 0.5, y: 0.55), CGPoint(x: 0.53, y: 0.57), CGPoint(x: 0.5, y: 0.56)] {
                withAnimation(.easeOut(duration: 0.15)) { tap = p }
                try? await Task.sleep(for: .milliseconds(260))
                withAnimation(.easeOut(duration: 0.2)) { tap = nil }
                try? await Task.sleep(for: .milliseconds(120))
            }
            withAnimation(.bouncy) { open = true }
            try? await Task.sleep(for: .milliseconds(650))
            for i in 0..<4 {
                withAnimation(.snappy) { pressed = String(Array(code)[i]); typed = i + 1 }
                try? await Task.sleep(for: .milliseconds(200)); withAnimation { pressed = nil }
                try? await Task.sleep(for: .milliseconds(300))
            }
            withAnimation(.bouncy) { done = true }
            try? await Task.sleep(for: .seconds(2.2))
        }
    }
}
