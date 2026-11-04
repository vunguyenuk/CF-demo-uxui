import SwiftUI
import PassKit
import AVFoundation
import MapKit

// MARK: - Looping muted video (Blender / Remotion clips)

struct LoopingVideoView: UIViewRepresentable {
    let name: String
    var gravity: AVLayerVideoGravity = .resizeAspectFill
    var loops = true
    var onEnd: (@MainActor @Sendable () -> Void)? = nil

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = gravity
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp4") else { return view }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        let item = AVPlayerItem(url: url)
        let player: AVPlayer
        if loops {
            let queue = AVQueuePlayer()
            context.coordinator.looper = AVPlayerLooper(player: queue, templateItem: item)
            player = queue
        } else {
            // A queue advances to an empty item at EOF. Keep this item and its last frame visible.
            player = AVPlayer(playerItem: item)
            player.actionAtItemEnd = .pause
            if let onEnd {
                context.coordinator.observer = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
                ) { _ in Task { @MainActor in onEnd() } }
            }
        }
        player.isMuted = true
        view.playerLayer.player = player
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        uiView.playerLayer.player?.pause()
        if let o = coordinator.observer { NotificationCenter.default.removeObserver(o) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var looper: AVPlayerLooper?; var observer: NSObjectProtocol? }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - Floating glass fact chip (Dopafit-style proof cards)

// MARK: - Map pin

// MARK: - Segmented progress (rent flow)

struct StepProgress: View {
    let current: Int
    let total: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? Theme.brand : Color.secondary.opacity(0.2))
                    .frame(height: 4)
                    .animation(.smooth(duration: 0.4).delay(Double(i) * 0.05), value: current)
            }
        }
    }
}

// MARK: - Kiosk slot diagram: which slot to take the charger from

struct SlotGrid: View {
    let highlight: Int          // 1-based slot number, counted left→right, top→bottom
    var columns = 6
    var rows = 4
    @State private var blink = false

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 8) {
            ForEach(0..<rows, id: \.self) { r in
                GridRow {
                    ForEach(0..<columns, id: \.self) { c in
                        let n = r * columns + c + 1
                        VStack(spacing: 3) {
                            Circle()
                                .fill(n == highlight ? Theme.brand : Theme.brand.opacity(0.35))
                                .frame(width: 5, height: 5)
                                .opacity(n == highlight && blink ? 0.2 : 1)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(n == highlight ? Theme.brand : Color(white: 0.16))
                                .frame(width: 12, height: 34)
                                .overlay {
                                    if n == highlight {
                                        RoundedRectangle(cornerRadius: 3).stroke(Theme.brand.opacity(0.5), lineWidth: 6)
                                            .scaleEffect(blink ? 1.4 : 1).opacity(blink ? 0 : 1)
                                    }
                                }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.white, in: .rect(cornerRadius: Theme.optionRadius, style: .circular))
        .overlay(RoundedRectangle(cornerRadius: Theme.optionRadius, style: .circular).strokeBorder(Color.black.opacity(0.06)))
        .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { blink = true } }
        .accessibilityLabel("Slot \(highlight) is flashing")
    }
}

// MARK: - Bolt confetti (receipt)

struct BoltConfetti: View {
    struct Piece { let x: Double; let delay: Double; let speed: Double; let spin: Double; let size: Double; let bolt: Bool; let hue: Int }
    private let pieces: [Piece] = (0..<70).map { i in
        let f = Double(i)
        return Piece(x: (f * 37).truncatingRemainder(dividingBy: 100) / 100,
                     delay: (f * 13).truncatingRemainder(dividingBy: 9) / 18,
                     speed: 0.55 + (f * 7).truncatingRemainder(dividingBy: 5) / 10,
                     spin: (f * 53).truncatingRemainder(dividingBy: 360),
                     size: 7 + (f * 3).truncatingRemainder(dividingBy: 7),
                     bolt: i % 4 == 0, hue: i % 3)
    }
    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                var bolt = ctx.resolve(Image(systemName: "bolt.fill"))
                bolt.shading = .color(Theme.brand)
                for p in pieces {
                    let local = t - p.delay
                    guard local > 0, local < 2.6 else { continue }
                    let y = -20 + local * local * 260 * p.speed + local * 120
                    let x = p.x * size.width + sin(local * 3 + p.spin) * 18
                    guard y < size.height + 20 else { continue }
                    ctx.opacity = max(0, 1 - local / 2.6)
                    let color: Color = [Theme.brand, Theme.success, Color(red: 1, green: 0.78, blue: 0.2)][p.hue]
                    if p.bolt {
                        var c = ctx
                        c.translateBy(x: x, y: y)
                        c.rotate(by: .degrees(p.spin + local * 180))
                        c.draw(bolt, in: CGRect(x: -p.size, y: -p.size, width: p.size * 2, height: p.size * 2))
                    } else {
                        var c = ctx
                        c.translateBy(x: x, y: y)
                        c.rotate(by: .degrees(p.spin + local * 240))
                        c.fill(Path(roundedRect: CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2), cornerRadius: 2), with: .color(color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .foregroundStyle(Theme.brand)
    }
}

// MARK: - Small helpers

struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(valueColor).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 2)
    }
}

/// Header hierarchy shared by the compact system sheets.
struct SheetHeading: View {
    let title: String
    var subtitle: String? = nil
    var onClose: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.body.weight(.semibold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(.primary)
                .accessibilityLabel("Close")
            }
        }
        .padding(.top, 8)
    }
}

/// A content-sized native sheet with the same visible footer inset across screens.
struct FittedActionSheet<Content: View>: View {
    var background: Color = Theme.groupedBackground
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 460

    var body: some View {
        ScrollView {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .ignoresSafeArea(.container, edges: .bottom)
        .presentationDetents([.height(max(1, contentHeight - ScreenInsets.bottom))])
        .presentationBackground(background)
        .presentationDragIndicator(.visible)
    }
}

struct UnlockCodeDigits: View {
    let code: String
    @ScaledMetric(relativeTo: .title) private var digitHeight: CGFloat = 56
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var play = false

    var body: some View {
        let playAnimation = !reduceMotion
        HStack(spacing: 8) {
            ForEach(Array(code.enumerated()), id: \.offset) { index, digit in
                Text(String(digit))
                    .font(.system(.title, design: .rounded).bold())
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, minHeight: digitHeight)
                    .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: Theme.fieldRadius, style: .circular))
                    .keyframeAnimator(initialValue: 0.0, trigger: play) { content, elapsed in
                        let progress = playAnimation ? min(1, max(0, (elapsed - Double(index) * 0.05) / 0.2)) : 1
                        let eased = 1 - pow(1 - progress, 3)
                        content
                            .rotation3DEffect(.degrees(-90 * (1 - eased)), axis: (x: 1, y: 0, z: 0))
                    } keyframes: { _ in
                        LinearKeyframe(0.35, duration: playAnimation ? 0.35 : 0)
                    }
            }
        }
        .id(code)
        .task(id: code) {
            do { try await Task.sleep(for: .milliseconds(32)) } catch { return }
            play.toggle()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Unlock code")
        .accessibilityValue(code.map(String.init).joined(separator: " "))
    }
}

/// Keep compact PassKit artwork inside the shared 46 pt capsule.
struct CheckoutApplePayButton: UIViewRepresentable {
    let type: PKPaymentButtonType
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    func makeUIView(context: Context) -> PaymentControl {
        let control = PaymentControl(type: type)
        let coordinator = context.coordinator
        control.addAction(UIAction { _ in coordinator.action() }, for: .touchUpInside)
        return control
    }

    func updateUIView(_ control: PaymentControl, context: Context) {
        context.coordinator.action = action
        control.isEnabled = enabled
        control.alpha = enabled ? 1 : 0.5
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PaymentControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: Theme.buttonHeight)
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    @MainActor final class Coordinator {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
    }

    final class PaymentControl: UIControl {
        private let artwork: PKPaymentButton

        init(type: PKPaymentButtonType) {
            artwork = PKPaymentButton(paymentButtonType: type, paymentButtonStyle: .black)
            super.init(frame: .zero)
            backgroundColor = .black
            layer.cornerRadius = Theme.buttonHeight / 2
            clipsToBounds = true
            artwork.isUserInteractionEnabled = false
            artwork.isAccessibilityElement = false
            addSubview(artwork)
            isAccessibilityElement = true
            accessibilityTraits = .button
            accessibilityLabel = type == .checkout ? "Check out with Apple Pay" : "Rent with Apple Pay"
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override var intrinsicContentSize: CGSize {
            CGSize(width: max(140, artwork.intrinsicContentSize.width), height: Theme.buttonHeight)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let height = min(bounds.height, max(36, artwork.intrinsicContentSize.height))
            artwork.frame = CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
        }

        override var isHighlighted: Bool {
            didSet { alpha = isHighlighted ? 0.85 : isEnabled ? 1 : 0.5 }
        }
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Theme.brand
    let action: () -> Void
    var body: some View {
        // Exactly Theme.buttonHeight tall: the system glass-prominent style adds its own padding around the
        // label (≈ 56 pt total), which read as too tall. Same look: solid fill, white label, soft press.
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).multilineTextAlignment(.center).lineLimit(2)
            }
            .font(.headline)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
        }
        .buttonStyle(FilledCapsuleStyle(tint: tint))
    }
}

struct FilledCapsuleStyle: ButtonStyle {
    var tint: Color
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? .white : Color(uiColor: .tertiaryLabel))
            .background(enabled ? tint : Color(uiColor: .tertiarySystemFill), in: Capsule(style: .circular))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(Capsule(style: .circular))
    }
}

/// Map pin: a circle that narrows into a point, drawn as a single path.
struct PinShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, c = CGPoint(x: r.midX, y: r.minY + w / 2), rad = w / 2 - 1.5
        var p = Path()
        p.addArc(center: c, radius: rad, startAngle: .degrees(130), endAngle: .degrees(50), clockwise: false)
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY - 2), control: CGPoint(x: r.midX + rad * 0.35, y: r.maxY - 10))
        p.addQuadCurve(to: CGPoint(x: c.x + rad * cos(.pi * 130 / 180), y: c.y + rad * sin(.pi * 130 / 180)),
                       control: CGPoint(x: r.midX - rad * 0.35, y: r.maxY - 10))
        p.closeSubpath()
        return p
    }
}

// MARK: - Floating bottom cards (iOS 26)

enum ScreenInsets {
    /// Home-indicator inset of the key window (34 pt on Face ID iPhones).
    @MainActor static var bottom: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom ?? 34
    }
}

extension View {
    /// Keeps the same inset at the sides and physical bottom, including in a full-screen cover.
    func floatingAtBottom(_ gap: CGFloat = 8) -> some View {
        padding(.horizontal, gap).padding(.bottom, gap - ScreenInsets.bottom)
    }
}

extension Shape where Self == ConcentricRectangle {
    /// Keep the web's top corners and let the lower corners follow the display.
    static func floatingPanel(top radius: CGFloat, minimumBottom: CGFloat) -> Self {
        .init(uniformTopCorners: .fixed(radius), uniformBottomCorners: .concentric(minimum: .fixed(minimumBottom)))
    }
}

// MARK: - Map zoom (+ / −), like the web prototype. Pinch still works; this is for one hand / the simulator.

struct MapZoomControl: View {
    var zoomIn: () -> Void
    var zoomOut: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Button(action: zoomIn) { Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).frame(width: Theme.iconButton, height: Theme.iconButton) }
                .accessibilityLabel("Zoom in")
            Divider().frame(width: 24)
            Button(action: zoomOut) { Image(systemName: "minus").font(.system(size: 18, weight: .semibold)).frame(width: Theme.iconButton, height: Theme.iconButton) }
                .accessibilityLabel("Zoom out")
        }
        .buttonStyle(.plain).foregroundStyle(Theme.ink)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

extension MapCamera {
    /// Same view, closer (k < 1) or further (k > 1).
    func zoomed(_ k: Double) -> MapCamera {
        MapCamera(centerCoordinate: centerCoordinate, distance: min(max(distance * k, 120), 60_000), heading: heading, pitch: pitch)
    }
}

extension MKPolyline {
    /// Where the walking route ends (on the street, in front of the venue).
    var lastCoordinate: CLLocationCoordinate2D { points()[max(pointCount - 1, 0)].coordinate }
}

extension MKPolyline {
    var walkingCoordinates: [CLLocationCoordinate2D] {
        let routePoints = points()
        return (0..<pointCount).map { routePoints[$0].coordinate }
    }
}

// MARK: - Walking directions

enum WalkDirections {
    /// Keep MapKit's start, destination and vertices intact. A failed request has no verified route.
    static func route(from a: CLLocation, to b: CLLocation) async -> MKRoute? {
        for attempt in 0..<2 {
            guard !Task.isCancelled else { return nil }
            let req = MKDirections.Request()
            req.source = MKMapItem(location: a, address: nil)
            req.destination = MKMapItem(location: b, address: nil)
            req.transportType = .walking
            if let route = try? await MKDirections(request: req).calculate().routes.first,
               route.polyline.pointCount > 1 { return route }
            if attempt == 0 { try? await Task.sleep(for: .milliseconds(900)) }
        }
        return nil
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        MKMapPoint(a).distance(to: MKMapPoint(b))
    }

    /// The road endpoint may be a curb or path near the venue. The indoor kiosk is a separate location.
    static func needsHandoff(for station: Station, from endpoint: CLLocationCoordinate2D) -> Bool {
        station.isInsideVenue || distance(endpoint, station.coordinate) > 10
    }
}

extension MKPolyline {
    var length: CLLocationDistance {
        let p = points(); var d = 0.0
        if pointCount > 1 { for i in 1..<pointCount { d += p[i - 1].distance(to: p[i]) } }
        return d
    }
}

/// Round glass icon button with NO extra outer padding (the system `.glass` + `.circle` style adds some,
/// which made round buttons bigger than the 44 pt capsule next to them). The label sets the size (44).
struct GlassCircleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .frame(width: Theme.iconButton, height: Theme.iconButton)
            .glassEffect(.regular.interactive(), in: .circle)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(.circle)
    }
}


// MARK: - Top banner (iOS notification style), same as the web prototype's banners
struct TopBanner: View {
    let icon: String
    var tint: Color = Theme.warning
    let title: String
    let message: String
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AppIcon(icon, size: 18).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(tint, in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(message).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
