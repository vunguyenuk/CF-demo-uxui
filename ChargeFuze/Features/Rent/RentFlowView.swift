import SwiftUI
import PassKit
import VisionKit
import AVFoundation

/// Scan → Pay → Take it → Charging, one screen with a 4-part progress bar (Dopafit-style steps).
struct RentFlowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.rentStep == .scan {
            ScanStep()   // full-screen camera, its own controls
                .transition(.opacity)
        } else if model.rentStep == .take || model.rentStep == .charging {
            Group { if model.rentStep == .take { TakeStep() } else { ChargingStep() } }
                .background(Color.white)
                .transition(.opacity)
        } else {
            stepsBody
        }
    }

    private var stepsBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    if model.rentStep == .pay { withAnimation(.smooth) { model.rentStep = .scan } }
                    else { model.finishRentFlow() }
                } label: {
                    Image(systemName: model.rentStep == .pay ? "chevron.left" : "xmark")
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(GlassCircleStyle())
                .disabled(model.rentStep == .take && !model.ejectFailed)
                .opacity(model.rentStep == .charging ? 0 : 1)

                VStack(alignment: .leading, spacing: 6) {
                    StepProgress(current: model.rentStep.rawValue, total: RentStep.allCases.count)
                    Text("Step \(model.rentStep.rawValue + 1) of 4 · \(model.rentStep.title)")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)

            Group {
                switch model.rentStep {
                case .scan: EmptyView()
                case .pay: CheckoutStep()
                case .take: TakeStep()
                case .charging: ChargingStep()
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(uiColor: .systemBackground))
        .sensoryFeedback(.success, trigger: model.rentStep == .charging)
    }
}

// MARK: - 1 · Scan

struct ScanStep: View {
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @State private var codeError: String?
    @State private var torch = false
    @FocusState private var codeFocused: Bool

    private let hole: CGFloat = 240

    var body: some View {
        ZStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    QRScannerView { payload in handle(payload) }
                } else {
                    // Simulator / mirroring: a looping camera view of the kiosk QR.
                    LoopingVideoView(name: "cam")
                }
            }
            .ignoresSafeArea()

            // Dim everything except the scan window.
            Rectangle().fill(.black.opacity(0.5))
                .reverseMask { RoundedRectangle(cornerRadius: 30, style: .circular).frame(width: hole, height: hole) }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            ScanCorners().stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .frame(width: hole + 6, height: hole + 6)
                .shadow(color: .black.opacity(0.3), radius: 6)
                .allowsHitTesting(false)
            ScanLine().frame(width: hole - 40, height: hole - 40).allowsHitTesting(false)

            VStack(spacing: 6) {
                Text("Scan the QR code on the kiosk").font(.title3.bold())
                Text("It's on the screen, under \u{201C}Portable chargers\u{201D}").font(.subheadline).opacity(0.85)
            }
            .foregroundStyle(.white).multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.4), radius: 8)
            .offset(y: -hole / 2 - 70)
            .padding(.horizontal, 24)

            VStack {
                HStack {
                    Button { model.finishRentFlow() } label: {
                        Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(.white).frame(width: 44, height: 44)
                    }
                    .buttonStyle(GlassCircleStyle())
                    Spacer()
                    Text("Step 1 of 4 · Scan").font(.footnote.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 36)
                        .glassEffect(.regular, in: .capsule)
                    Spacer()
                    Button { torch.toggle(); setTorch(torch) } label: {
                        Image(systemName: torch ? "flashlight.on.fill" : "flashlight.off.fill").foregroundStyle(torch ? Color.yellow : .white).frame(width: 44, height: 44)
                    }
                    .buttonStyle(GlassCircleStyle())
                    .accessibilityLabel("Flashlight")
                }
                .environment(\.colorScheme, .dark)
                .padding(.horizontal, Theme.cardInset).padding(.top, Theme.cardInset)

                Spacer()

                VStack(spacing: 10) {
                    if let codeError {
                        Text(codeError).font(.footnote).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.5))
                            .multilineTextAlignment(.center)
                    }

                    // Demo: no camera through screen mirroring / simulator
                    Button {
                        handle("chargefuze://station/\((model.rentStation ?? model.nearestWithChargers ?? model.stations[0]).id)")
                    } label: {
                        Label("Scan demo QR", systemImage: "qrcode.viewfinder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: Theme.buttonHeight)
                    }
                    .buttonStyle(FilledCapsuleStyle(tint: Theme.ink))
                    .accessibilityHint("Simulates scanning \((model.rentStation ?? model.nearestWithChargers ?? model.stations[0]).id)")
                }
                .floatingAtBottom(Theme.cardInset)
            }
        }
        .background(.black)
        .sensoryFeedback(.error, trigger: codeError)
        .onDisappear { setTorch(false) }
    }

    private func setTorch(_ on: Bool) {
        guard let d = AVCaptureDevice.default(for: .video), d.hasTorch, (try? d.lockForConfiguration()) != nil else { return }
        d.torchMode = on ? .on : .off
        d.unlockForConfiguration()
    }

    private func submitCode() {
        if let s = model.station(withCode: code) { codeFocused = false; accept(s) }
        else { withAnimation { codeError = "We couldn't find \(code.uppercased()). Check the code under the QR." } }
    }

    private func handle(_ payload: String) {
        let code = payload.components(separatedBy: "/").last ?? payload
        if let s = model.station(withCode: code) { accept(s) }
        else { withAnimation { codeError = "This QR isn't a chargeFUZE kiosk." } }
    }

    private func accept(_ s: Station) {
        guard s.status == .online, s.chargers > 0 else {
            withAnimation { codeError = s.status == .offline ? "\(s.venue) is offline right now." : "\(s.venue) has no chargers right now. Try \(model.nearestWithChargers?.venue ?? "another station")." }
            return
        }
        codeError = nil
        model.didScan(s)
    }
}

struct ScanCorners: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); let l: CGFloat = 36
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

struct ScanLine: View {
    @State private var down = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { g in
            LinearGradient(colors: [Theme.brand.opacity(0), Theme.brand.opacity(0.8), Theme.brand.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(height: 3)
                .shadow(color: Theme.brand, radius: 8)
                .offset(y: down ? g.size.height : 0)
        }
        .opacity(reduceMotion ? 0 : 1)
        .onAppear { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { down = true } }
        .allowsHitTesting(false)
    }
}

/// VisionKit live QR scanner.
struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                           qualityLevel: .balanced, isHighlightingEnabled: false)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var last = ""
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let b) = item, let s = b.payloadStringValue, s != last {
                    last = s
                    DispatchQueue.main.async { self.onCode(s) }
                }
            }
        }
    }
}

// MARK: - 2 · Pay (one price, said plainly)

struct CheckoutStep: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let s = model.rentStation {
            CheckoutFlow(station: s, mode: .rent) { model.pay() }
        }
    }
}

struct PaymentMethodPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                ForEach(model.paymentMethods) { pm in
                    Button {
                        guard pm.isUsable else { return }
                        model.defaultPaymentID = pm.id
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: pm.systemImage).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pm.title).font(.body.weight(.semibold))
                                if let sub = pm.subtitle { Text(sub).font(.subheadline).foregroundStyle(pm.isUsable ? Color.secondary : Theme.danger) }
                            }
                            Spacer()
                            if model.defaultPaymentID == pm.id { AppIcon("checkmark", size: 18).foregroundStyle(Theme.brand) }
                        }
                        .foregroundStyle(pm.isUsable ? Color.primary : Color.secondary)
                    }
                    .disabled(!pm.isUsable)
                }
            }
            .navigationTitle("Pay with").navigationBarTitleDisplayMode(.inline)
        }
        .sensoryFeedback(.selection, trigger: model.defaultPaymentID)
    }
}

// MARK: - 3 · Take it (Blender eject clip + the flashing slot)

struct TakeStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.ejectFailed {
            ScrollView {
                FixGuideView(kind: .noEject,
                             onPrimary: { model.pay() },                                                   // release a different charger
                             onSecondary: { model.finishRentFlow() })                      // cancel, no charge
                    .padding(.top, 40)
            }
            .sensoryFeedback(.warning, trigger: model.ejectFailed)
        } else if model.waitingForRelease {
            VStack(spacing: 12) {
                ProgressView()
                Text("Waiting for the kiosk").font(.headline)
                Text("We'll let you know when a charger is ready.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Blender clip of the charger sliding out, full-bleed; the copy sits on white below it
            ZStack(alignment: .bottom) {
                LoopingVideoView(name: "eject").ignoresSafeArea()
                LinearGradient(stops: [.init(color: .white.opacity(0), location: 0), .init(color: .white, location: 0.42)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 420).ignoresSafeArea(edges: .bottom).allowsHitTesting(false)
                VStack(spacing: 10) {
                    Text("Take the charger that popped out").font(.system(size: 30, weight: .bold))
                        .multilineTextAlignment(.center).contentTransition(.numericText())
                    Text("Its light is flashing blue. Pull it straight out.").foregroundStyle(.secondary)
                    HStack(spacing: 10) { ProgressView(); Text("Releasing the charger…").fontWeight(.semibold) }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color(uiColor: .secondarySystemBackground), in: .capsule)
                        .padding(.top, 6)
                    Text("Nothing comes out in 20 s? We cancel it. No charge.").font(.footnote).foregroundStyle(.secondary)
                }
                .floatingAtBottom(Theme.cardInset)
            }
        }
    }
}

// MARK: - 4 · Charging

struct ChargingStep: View {
    @Environment(AppModel.self) private var model
    @State private var showChargingHelp = false
    @State private var requestedSwap = false

    var body: some View {
        VStack(spacing: 0) {
            LoopingVideoView(name: "charging", loops: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea(.container, edges: [.top, .horizontal])

            VStack(spacing: 8) {
                Text("Plug the cable into your phone").font(.title2.bold()).multilineTextAlignment(.center)
                Text("Your time has started. Return it to any station.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                PrimaryButton(title: "Done", systemImage: "checkmark") { model.finishRentFlow() }
                    .padding(.top, 8)
                Button("Not charging?") { showChargingHelp = true }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: Theme.buttonHeight)
            }
            .padding(.top, Theme.cardInset)
            .floatingAtBottom(Theme.cardInset)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showChargingHelp, onDismiss: {
            if requestedSwap { model.finishRentFlow(reportNotCharging: true) }
        }) {
            FixGuideSheet(kind: .notCharging, onPrimary: { requestedSwap = true })
        }
        .overlay(alignment: .top) {
            BoltConfetti().frame(maxHeight: 460).clipped().allowsHitTesting(false).ignoresSafeArea()
        }
    }

    private func fact(_ icon: String, _ color: Color, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 14) {
            IconTile(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(sub).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}

extension View {
    /// Cuts `mask` out of this view (used for the scan window).
    func reverseMask<M: View>(@ViewBuilder _ mask: () -> M) -> some View {
        self.mask {
            Rectangle().overlay { mask().blendMode(.destinationOut) }.compositingGroup()
        }
    }
}
