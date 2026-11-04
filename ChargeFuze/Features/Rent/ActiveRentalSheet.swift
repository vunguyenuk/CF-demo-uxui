import SwiftUI

/// Opened from the mini-player: time, cost, next block, deadlines, and the two things you can do.
struct ActiveRentalSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var compactHeight: CGFloat = 214
    @State private var fullHeight: CGFloat = 520
    @State private var open = false
    private var compact: PresentationDetent { .height(max(1, compactHeight - ScreenInsets.bottom)) }
    private var expanded: PresentationDetent { .height(max(compactHeight + 1, fullHeight) - ScreenInsets.bottom) }
    private var selectedDetent: Binding<PresentationDetent> {
        Binding(get: { open ? expanded : compact }, set: { open = $0 == expanded })
    }

    var body: some View {
        // iOS 26 floating sheet: one glass card, no nav bar (header row instead)
        Group {
            if let r = model.activeRental {
                // small detent shows the top; dragging up grows the sheet (native, follows the finger) to reveal the details
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in content(r, now: ctx.date) }
                        .padding(Theme.cardInset)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }   // expanded = exactly the content
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(.container, edges: .bottom)
            } else {
                ContentUnavailableView { Label("No rental", symbol: "bolt.slash") }
            }
        }
        .presentationDetents([compact, expanded], selection: selectedDetent)
        .presentationContentInteraction(.resizes)
        .presentationBackground(Theme.groupedBackground)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: open)
    }

    @ViewBuilder
    private func content(_ r: Rental, now: Date) -> some View {
        let next = r.nextChargeIn(at: now)
        let warn = (next ?? .infinity) < 300
        let tint: Color = warn ? Theme.warning : Theme.success
        let block = r.rate.blockMinutes * 60
        VStack(alignment: .leading, spacing: Theme.cardInset) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.elapsed(at: now).clock).font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit().foregroundStyle(tint).contentTransition(.numericText())
                        Text(subline(r, now: now, next: next, warn: warn)).font(.subheadline).foregroundStyle(.secondary)
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 0)
                    Button { withAnimation(.smooth(duration: 0.4)) { open.toggle() } } label: {
                        Image(systemName: open ? "chevron.down" : "chevron.up")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(.primary)
                    .accessibilityLabel(open ? "Hide details" : "Show details")
                }
                // progress to the next charge
                ProgressView(value: next.map { max(0.02, (block - $0) / block) } ?? 1).tint(tint)
                PrimaryButton(title: "Find a kiosk", systemImage: "location.fill", tint: Theme.ink) { dismiss(); model.startReturnFlow() }
                Button {
                    dismiss()
                    Task { try? await Task.sleep(for: .milliseconds(350)); model.showSwapReasons = true }   // what's wrong? → swap
                } label: {
                    Text("Charger not working?").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
                }
                .tint(Theme.brand)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                compactHeight = $0 + 2 * Theme.cardInset
            }
            // The native expanded detent reveals these details.
            VStack(spacing: 0) {
                row("Picked up", r.station.venue, "\(r.startedAt.shortTime) · \(r.station.kioskLocation)")
                row("Paying with", r.payment.title, nil)
                row("Price", "\(r.rate.pricePerBlock.usd) / \(r.rate.blockLabel)", "Max \(r.rate.dailyMax.usd) a day")
                row("Return by", "\(Int(r.rate.nonReturnHours)) h after pickup", "\(r.rate.hold.usd) hold released on return")
            }
            .padding(.horizontal, 16)
            .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: Theme.noticeRadius, style: .circular))
        }
    }

    private func subline(_ r: Rental, now: Date, next: TimeInterval?, warn: Bool) -> String {
        let so = "\(r.cost(at: now).usd) so far"
        guard let next else { return "\(so) · today's max reached" }
        return warn ? "\(so) · return in \(Int(next / 60) + 1) min to stay at \(r.cost(at: now).usd)"
                    : "\(so) · +\(r.rate.pricePerBlock.usd) in \(next.clock)"
    }

    private func row(_ k: String, _ v: String, _ sub: String?) -> some View {
        VStack(spacing: 0) {
            if k != "Picked up" { Divider() }
            HStack(alignment: .firstTextBaseline) {
                Text(k).foregroundStyle(.secondary)
                Spacer(minLength: 16)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(v).fontWeight(.medium).multilineTextAlignment(.trailing)
                    if let sub { Text(sub).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func deadline(_ icon: String, _ title: String, _ value: String, _ tint: Color, done: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.footnote.weight(.bold)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(done ? tint : tint.opacity(0.35), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(value).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    /// Venue closing time from the station hours text ("Open 11 AM – 2 AM"), demo-grade parsing.
    private func closingTime(for s: Station, now: Date) -> String? {
        guard let dash = s.hours.range(of: "– ") else { return nil }
        let close = String(s.hours[dash.upperBound...])
        return close.contains("M") ? "Today at \(close) · return before then or use another station" : nil
    }
}
