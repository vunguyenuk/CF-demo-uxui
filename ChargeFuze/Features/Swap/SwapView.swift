import SwiftUI
import AVFoundation

/// Charger not working → swap it, designed to be read at a glance while looking at the kiosk:
/// one big slot "beacon" that blinks in step with the kiosk's slot light, a 2-word verb,
/// auto-advance on kiosk events (no buttons), haptics + optional spoken cues.
struct SwapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    enum Phase: Int { case putBack = 1, opening, take, done }
    @State private var phase: Phase = .putBack
    @State private var newSlot = 4
    @State private var blink = false
    @State private var voice = true
    @State private var showFix = false
    @State private var speech = AVSpeechSynthesizer()

    /// Clear, friendly female English voice, best installed quality (premium > enhanced): Ava, Zoe, Samantha…
    static let maleVoice: AVSpeechSynthesisVoice? = {
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        for name in ["Ava", "Zoe", "Samantha", "Allison", "Susan", "Karen"] {
            if let v = all.filter({ $0.name.contains(name) }).max(by: { $0.quality.rawValue < $1.quality.rawValue }) { return v }
        }
        return all.filter { $0.gender == .female }.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    private var oldSlot: Int { model.activeRental?.slot ?? 12 }
    private var slot: Int { phase == .putBack ? oldSlot : newSlot }

    var body: some View {
        ZStack(alignment: .bottom) {
            LoopingVideoView(name: phase == .putBack ? "insert" : "eject").id(phase == .putBack).ignoresSafeArea()
                .transition(.opacity)
            LinearGradient(colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 18) {
                hud
                if phase == .done {
                    PrimaryButton(title: "Done") { dismiss() }.transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .floatingAtBottom(Theme.cardInset)
        }
        .overlay(alignment: .top) { topBar }
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.impact(weight: .heavy), trigger: phase)
        .task(id: showFix) {
            guard !showFix else { return }
            await run()
        }
        .onDisappear { speech.stopSpeaking(at: .immediate) }
        .sheet(isPresented: $showFix) { FixGuideSheet(kind: .wontInsert).preferredColorScheme(.light) }
        .onAppear { withAnimation(.easeInOut(duration: 0.5).repeatForever()) { blink = true } }
    }

    // stories-style progress + close + voice toggle
    private var topBar: some View {
        HStack(spacing: 12) {
            Button { speech.stopSpeaking(at: .immediate); dismiss() } label: { AppIcon("xmark", size: 18).frame(width: 44, height: 44) }
                .buttonStyle(GlassCircleStyle())
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { i in
                    Capsule().fill(.white.opacity(i <= min(phase.rawValue, 3) ? 1 : 0.3)).frame(height: 4)
                }
            }
            Button { voice.toggle(); if !voice { speech.stopSpeaking(at: .immediate) } } label: {
                AppIcon(voice ? "speaker.wave.2.fill" : "speaker.slash.fill", size: 16).frame(width: 44, height: 44)
            }
            .buttonStyle(GlassCircleStyle()).accessibilityLabel("Voice guide")
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    // the beacon: huge slot number that blinks like the kiosk light, plus a 2-word verb
    private var hud: some View {
        HStack(spacing: 12) {
            ZStack {
                switch phase {
                case .opening:
                    Circle().fill(.white.opacity(0.14))
                    Circle().trim(from: 0, to: 0.28).stroke(.white, style: .init(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(blink ? 360 : 0))
                    beaconText
                case .done:
                    Circle().fill(Theme.success.opacity(0.22))
                    AppIcon("checkmark", size: 38).foregroundStyle(Color(red: 0.37, green: 0.88, blue: 0.54))
                default:
                    // a status indicator, not a button: soft tint + ripple, no solid fill
                    Circle().fill(Theme.brand.opacity(0.2))
                    Circle().stroke(Color(red: 0.49, green: 0.75, blue: 1).opacity(blink ? 0 : 0.55), lineWidth: 2)
                        .scaleEffect(blink ? 1.35 : 1)
                    beaconText.foregroundStyle(Color(red: 0.49, green: 0.75, blue: 1))
                }
            }
            .frame(width: 68, height: 68)
            VStack(alignment: .leading, spacing: 8) {
                Text(verb).font(.title2.bold()).contentTransition(.opacity)
                Text(sub).font(.subheadline).foregroundStyle(.white.opacity(0.78))
                if phase == .putBack {
                    Button("Not clicking?") { showFix = true }.font(.subheadline.weight(.semibold)).foregroundStyle(Color(red: 0.62, green: 0.82, blue: 1))
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.regularMaterial, in: Capsule(style: .circular))
        .animation(.spring(duration: 0.45, bounce: 0.35), value: phase)
    }

    // any slot works, so the beacon shows the action, not a slot number
    private var beaconText: some View {
        AppIcon(phase == .putBack ? "arrow.down" : phase == .opening ? "bolt.fill" : "arrow.up", size: phase == .opening ? 26 : 30)
            .contentTransition(.symbolEffect(.replace))
    }

    private var verb: String {
        switch phase { case .putBack: "Put it back"; case .opening: "Opening"; case .take: "Take it"; case .done: "Swapped" }
    }
    private var sub: String {
        switch phase {
        case .putBack: "Any empty slot · push until it clicks"
        case .opening: "Kiosk is releasing a new one"
        case .take: "Grab the one that popped out"
        case .done: "Rental continues · faulty time removed"
        }
    }

    private func say(_ t: String) {
        guard voice else { return }
        speech.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: t)
        u.voice = Self.maleVoice; u.rate = AVSpeechUtteranceDefaultSpeechRate; u.pitchMultiplier = 1.0
        speech.speak(u)
    }

    /// Production: each step advances on a kiosk event (faulty charger seated → new one released → new one removed).
    private func run() async {
        guard let rental = model.activeRental else { return }
        let previousSlot = rental.slot
        newSlot = [4, 9, 15, 20].first { $0 != previousSlot } ?? 4
        say("Pop it back into any empty slot. Push till it clicks.")
        do { try await Task.sleep(for: .seconds(4.5)) } catch { return }
        withAnimation(.smooth(duration: 0.4)) { phase = .opening }; say("Got it. Grabbing you a fresh one.")
        do { try await Task.sleep(for: .seconds(2.6)) } catch { return }
        withAnimation { phase = .take }; say("There you go. Take the one that popped out.")
        do { try await Task.sleep(for: .seconds(3.6)) } catch { return }
        guard model.activeRental?.id == rental.id else { return }
        model.completeDemoSwap(rentalID: rental.id, oldSlot: previousSlot, newSlot: newSlot)
        withAnimation(.bouncy) { phase = .done }; say("All set. You're good to go.")
    }
}
