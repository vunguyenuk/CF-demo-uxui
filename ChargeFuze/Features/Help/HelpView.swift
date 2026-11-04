import SwiftUI

/// Help is an assistant that acts, not a queue: nobody staffs support, so it checks the kiosk log,
/// the phone's return proof and the account's history, then fixes the charge on the spot.
/// Only what it can't decide goes to the team, with everything attached and an honest reply time.
struct HelpView: View {
    @Environment(AppModel.self) private var model
    @State private var chat: [ChatItem] = []
    @State private var busy = false
    @State private var typing = false
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var listening = false
    @State private var heard = ""

    private let quick: [(IssueKind, String)] = [
        (.returnedStillCharged, "I returned it but I'm still being charged"),
        (.noEject, "The kiosk didn't give me a charger"),
        (.notCharging, "My charger isn't charging"),
        (.unexpectedCharge, "Why was I charged this much?"),
        (.other, "When do I get my $10 back?")
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(chat) { item in row(item).id(item.id) }
                        if typing { TypingBubble().id("typing") }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: chat.count) { withAnimation(.smooth) { proxy.scrollTo(chat.last?.id, anchor: .bottom) } }
                .onChange(of: typing) { if typing { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } } }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaBar(edge: .bottom) { composer }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { model.showHelp = false }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 10) {
                        AssistantAvatar(size: 32)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("chargeFUZE Assistant").font(.headline)
                            Text("Checks kiosk logs · fixes charges").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task { if chat.isEmpty { greet() } }
            .overlay { if listening { VoiceOverlay(text: heard) { listening = false }.transition(.opacity) } }
        }
    }

    // MARK: Rows
    @ViewBuilder private func row(_ item: ChatItem) -> some View {
        switch item.kind {
        case .ai(let t):
            Text(t).font(.body).padding(.horizontal, 15).padding(.vertical, 11)
                .background(.background, in: .rect(cornerRadius: Theme.cardRadius, style: .circular))
                .frame(maxWidth: 320, alignment: .leading)
                .transition(.scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity))
        case .me(let t):
            HStack { Spacer(minLength: 60)
                Text(t).font(.body).foregroundStyle(.white).padding(.horizontal, 15).padding(.vertical, 11)
                    .background(Theme.brand, in: .rect(cornerRadius: Theme.cardRadius, style: .circular))
            }
            .transition(.scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity))
        case .context(let title, let sub):
            HStack(spacing: 12) {
                IconTile(icon: "bolt.fill", color: Theme.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(sub).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: .rect(cornerRadius: Theme.cardRadius, style: .circular))
        case .step(let t, let done):
            HStack(spacing: 10) {
                if done { AppIcon("checkmark", size: 16).foregroundStyle(Theme.success) }
                else { ProgressView().controlSize(.small) }
                Text(t).font(.subheadline).foregroundStyle(done ? .primary : .secondary)
            }
            .padding(.horizontal, 6)
        case .action(let a):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    IconTile(icon: a.icon, color: a.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.title).font(.headline)
                        Text(a.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if let label = a.action {
                    Button { model.showHelp = false; Task { try? await Task.sleep(for: .milliseconds(450)); model.showSwap = true } } label: {
                        Label(label, symbol: "arrow.clockwise").font(.headline).frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
                    }
                    .buttonStyle(FilledCapsuleStyle(tint: Theme.brand))
                }
                if !a.rows.isEmpty {
                    Divider()
                    ForEach(a.rows.indices, id: \.self) { i in let r = a.rows[i]
                        HStack { Text(r.0).foregroundStyle(.secondary); Spacer(); Text(r.1).fontWeight(.semibold) }.font(.subheadline)
                    }
                }
            }
            .padding(16)
            .background(.background, in: .rect(cornerRadius: Theme.groupRadius, style: .circular))
            .shadow(color: .black.opacity(0.05), radius: 12, y: 6)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if !busy {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quick, id: \.1) { q in
                            Button(q.1) { ask(q.0, q.1) }
                                .font(.subheadline.weight(.medium))
                                .frame(minHeight: Theme.buttonHeight)
                                .padding(.horizontal, 14)
                                .background(Theme.brandSoft, in: .capsule)
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            HStack(spacing: 8) {
                TextField("Describe the problem…", text: $text)
                    .focused($focused).submitLabel(.send).onSubmit(sendTyped)
                Button { startVoice() } label: { AppIcon("mic", size: 18).frame(width: Theme.buttonHeight, height: Theme.buttonHeight) }
                    .buttonStyle(GlassCircleStyle()).disabled(busy)
                    .accessibilityLabel("Talk to the assistant")
                Button(action: sendTyped) { AppIcon("arrow.up", size: 18).frame(width: Theme.buttonHeight, height: Theme.buttonHeight) }
                    .buttonStyle(FilledCapsuleStyle(tint: Theme.brand))
                    .accessibilityLabel("Send message")
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
            .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6)
            .background(.regularMaterial, in: .capsule)
            .padding(.horizontal, Theme.cardInset).padding(.bottom, 8)
        }
    }

    // MARK: Logic
    private func greet() {
        chat.append(.init(.ai("Hi Vu. I can check the kiosk records and fix most problems right here, usually in under a minute.")))
        if let r = model.activeRental {
            chat.append(.init(.context("Renting now · \(r.station.venue)", "\(r.elapsed().clock) · \(r.cost().usd) so far")))
        } else if let h = model.history.first {
            chat.append(.init(.context("Last rental · \(h.pickup.venue)", "\(h.endedAt.shortDay) · \(h.duration.friendly) · \(h.total.usd)")))
        }
    }

    /// Voice: hold a conversation instead of typing. Demo transcript; production uses SFSpeechRecognizer.
    private func startVoice() {
        guard !busy else { return }
        heard = ""; withAnimation(.smooth) { listening = true }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            for w in "My charger isn't charging".split(separator: " ") {
                guard listening else { return }
                try? await Task.sleep(for: .milliseconds(220))
                withAnimation(.snappy) { heard += (heard.isEmpty ? "" : " ") + w }
            }
            try? await Task.sleep(for: .milliseconds(600))
            guard listening else { return }
            withAnimation(.smooth) { listening = false }
            ask(.notCharging, heard)
        }
    }

    private func sendTyped() {
        let t = text.trimmingCharacters(in: .whitespaces); guard !t.isEmpty else { return }
        text = ""; focused = false
        let l = t.lowercased()
        let k: IssueKind = l.contains("return") || l.contains("still") ? .returnedStillCharged
            : (l.contains("eject") || l.contains("release") || l.contains("didn")) ? .noEject
            : (l.contains("not charg") || l.contains("dead") || l.contains("broken")) ? .notCharging
            : (l.contains("much") || l.contains("price") || l.contains("charged")) ? .unexpectedCharge : .other
        ask(k, t)
    }

    private func ask(_ kind: IssueKind, _ said: String) {
        guard !busy else { return }
        busy = true
        withAnimation(.snappy) { chat.append(.init(.me(said))) }
        Task {
            let rid = model.activeRental?.id ?? model.history.first?.id ?? "R-8F21C4"
            let h = model.history.first
            switch kind {
            case .returnedStillCharged:
                await say("Let me check the kiosk and your phone's return signal.")
                await step("Kiosk log · slot \(h?.returnSlot ?? 7) reported a charger")
                await step("Your phone was 0.4 m from the kiosk (Bluetooth)")
                await step("Account in good standing · 23 on-time returns")
                model.ledger.insert(ChargeLine(id: UUID().uuidString, kind: .refund, amount: 1, date: .now, state: .refunded, rentalID: rid,
                                               title: "Refund · billing after return", detail: "Time after your return was removed automatically."), at: 0)
                show(.init(icon: "checkmark.circle.fill", color: Theme.success, title: "Fixed · $1.00 refunded",
                           subtitle: "Billing now stops at the moment you returned it",
                           rows: [("Rental", rid), ("Refund to", "Apple Pay"), ("Shows up", "in 1–3 days")]))
                await say("Done. Nothing else needed from you. It's also in Rentals › Money activity.")
            case .noEject:
                await say("Checking whether a charger actually left the kiosk.")
                await step("No charger left any slot after your payment")
                await step("Rental cancelled · hold released")
                show(.init(icon: "checkmark.circle.fill", color: Theme.success, title: "Not charged",
                           subtitle: "Your $10 hold was released right away", rows: [("Charged", "$0.00"), ("Hold", "Released")]))
                await say("Sorry about that. The kiosk has been flagged for a technician.")
            case .notCharging:
                await say("Let's get you a working one.")
                await step("Charger flagged as faulty")
                await step("Clock paused on this charger")
                show(.init(icon: "arrow.clockwise", color: Theme.brand, title: "Free swap",
                           subtitle: "Put this one back, take a new one. The time on this one is removed.", rows: [], action: "Swap my charger"))
            case .unexpectedCharge:
                let total = h?.total ?? 2, blocks = h?.blocks ?? 2
                await say("Here's exactly how \(total.usd) adds up.")
                await step("Pulled the rental record")
                show(.init(icon: "creditcard.fill", color: Theme.brand, title: "\(total.usd) · \(blocks) × $1.00 per 30 min",
                           subtitle: h.map { "\($0.duration.friendly), \($0.pickup.venue) to \($0.dropoff.venue)" } ?? "",
                           rows: [("Each started 30 min", "$1.00"), ("Daily maximum", "$15.00"), ("The $10 hold", "Not a charge")]))
                await say("That matches the posted price. If something still looks off, tell me what you expected.")
            case .other:
                if said.contains("$10") || said.lowercased().contains("hold") {
                    await say("Your $10 hold isn't a charge.")
                    await step("Hold for \(rid) released by chargeFUZE")
                    show(.init(icon: "lock.open.fill", color: Theme.success, title: "Released",
                               subtitle: "Your bank removes it in up to 5 business days",
                               rows: [("Statement name", "FUZE TECHNOLOGY"), ("Status", "Released")]))
                } else {
                    await say("Got it. I've saved this with your rental, the kiosk log and your location so nobody needs to ask you again.")
                    let t = model.openTicket(.other, rentalID: rid, note: said)
                    show(.init(icon: "calendar", color: Theme.warning, title: "Sent to the chargeFUZE team",
                               subtitle: "You'll get an email reply within 1 business day", rows: [("Case", t.id)]))
                }
            }
            busy = false
        }
    }

    @MainActor private func say(_ t: String) async {
        withAnimation { typing = true }
        try? await Task.sleep(for: .milliseconds(700))
        withAnimation(.snappy) { typing = false; chat.append(.init(.ai(t))) }
    }
    @MainActor private func step(_ t: String) async {
        let item = ChatItem(.step(t, done: false))
        withAnimation(.snappy) { chat.append(item) }
        try? await Task.sleep(for: .milliseconds(850))
        if let i = chat.firstIndex(where: { $0.id == item.id }) { withAnimation { chat[i].kind = .step(t, done: true) } }
    }
    private func show(_ a: ActionCard) {
        withAnimation(.bouncy) { chat.append(.init(.action(a))) }
    }
}

// MARK: - Chat model

struct ActionCard: Hashable {
    let icon: String; let color: Color; let title: String; let subtitle: String; let rows: [(String, String)]
    var action: String? = nil
    static func == (l: ActionCard, r: ActionCard) -> Bool { l.title == r.title && l.subtitle == r.subtitle }
    func hash(into h: inout Hasher) { h.combine(title); h.combine(subtitle) }
}

struct ChatItem: Identifiable {
    enum Kind { case ai(String), me(String), context(String, String), step(String, done: Bool), action(ActionCard) }
    let id = UUID()
    var kind: Kind
    init(_ kind: Kind) { self.kind = kind }
}

struct AssistantAvatar: View {
    var size: CGFloat = 44
    var body: some View {
        Circle()
            .fill(AngularGradient(colors: [Theme.brand, Color(red: 0.37, green: 0.7, blue: 1), Color(red: 0.48, green: 0.36, blue: 1), Theme.brand], center: .center))
            .frame(width: size, height: size)
            .overlay(AppIcon("sparkles", size: size * 0.45).foregroundStyle(.white))
    }
}

struct TypingBubble: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle().fill(Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
                    .offset(y: on ? -3 : 2)
                    .animation(.easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.15), value: on)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 15)
        .background(.background, in: .rect(cornerRadius: Theme.cardRadius, style: .circular))
        .onAppear { on = true }
    }
}

/// iOS Settings-style coloured square with a white SF Symbol.
struct IconTile: View {
    let icon: String
    var color: Color = Theme.brand
    var body: some View {
        AppIcon(icon, size: 18).foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(color, in: .rect(cornerRadius: 9, style: .continuous))
    }
}

struct VoiceOverlay: View {
    let text: String
    var onCancel: () -> Void
    @State private var spin = false
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(AngularGradient(colors: [Theme.brand, Color(red: 0.37, green: 0.7, blue: 1), Color(red: 0.48, green: 0.36, blue: 1), Theme.brand], center: .center))
                    .frame(width: 150, height: 150).blur(radius: 8)
                    .rotationEffect(.degrees(spin ? 360 : 0)).scaleEffect(spin ? 1.08 : 0.96)
                Circle().fill(.white.opacity(0.9)).frame(width: 82, height: 82)
            }
            .padding(.bottom, 20)
            Text(text.isEmpty ? "Listening…" : text).font(.title2.bold()).multilineTextAlignment(.center)
                .contentTransition(.opacity).padding(.horizontal, 30)
            Text("Say what happened").foregroundStyle(.secondary)
            Button(action: onCancel) {
                Text("Cancel").font(.headline).padding(.horizontal, 20).frame(height: Theme.buttonHeight)
            }
            .buttonStyle(FilledCapsuleStyle(tint: Theme.ink)).padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onAppear { withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { spin = true } }
        .sensoryFeedback(.start, trigger: true)
    }
}
