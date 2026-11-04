import SwiftUI
import PassKit

/// Checkout used by scan-to-rent and by "Phone about to die? Pay now".
/// Client feedback: 1) Select pricing — every plan is fully readable (price, max, what's included, lost-charger note);
/// 2) Rent a charger — kiosk, the chosen plan again in full, promo, payment, then the Rent button. One sheet, no new screen.
struct CheckoutFlow: View {
    enum Mode { case rent, code }
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let station: Station
    var mode: Mode = .rent
    var pickupMinutes: Int? = nil
    var onPay: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingPaid = false
    @State private var step = 0            // 0 = pricing, 1 = summary
    @State private var pickPay = false
    @State private var promoEditing = false
    @State private var promoText = ""
    @State private var promo: String?
    @State private var summaryHeight: CGFloat = 398
    @State private var footerHeight = Theme.buttonHeight + Theme.cardInset

    struct PlanInfo { let plan: RentPlan; let name, price, max: String; let points: [String]; let note: String }
    private var plans: [PlanInfo] {
        let r = station.rate
        let lost = "Return within \(Int(r.nonReturnHours)) h to avoid the \(r.nonReturnFee.usd) lost-charger fee."
        return [
            .init(plan: .payAsYouGo, name: "Pay as you go", price: "\(r.pricePerBlock.usd) / \(r.blockLabel)", max: "Max \(r.dailyMax.usd) a day",
                  points: ["1 charger", "Pay only for the time you use", "First 3 min free"], note: lost),
            .init(plan: .dayPass, name: "Day pass", price: "$6.99", max: "24 hours",
                  points: ["Unlimited rentals for 24 h", "Swap chargers at any kiosk"], note: "Each charger still needs to be back within \(Int(r.nonReturnHours)) h."),
            .init(plan: .hourly, name: "Hourly", price: "$2.99 first hour", max: "then $1.49 / h",
                  points: ["1 charger", "Never more than \(r.dailyMax.usd) a day"], note: lost),
        ]
    }
    private var chosen: PlanInfo { plans.first { $0.plan == model.plan } ?? plans[0] }

    var body: some View {
        if model.signedIn { content } else { SignInView() }   // compact sign-in sheet (like the web), only when paying; it sizes itself per step
    }

    private var content: some View {
        VStack(spacing: 0) {
            if step == 0 {
                header
                ScrollView {
                    pricing.padding(.horizontal, Theme.cardInset).padding(.bottom, Theme.cardInset)
                }
                .scrollIndicators(.hidden)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        header
                        summary.padding(.horizontal, Theme.cardInset).padding(.bottom, Theme.cardInset)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { summaryHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            footer
                .padding(.horizontal, Theme.cardInset)
                .padding(.top, step == 0 ? Theme.cardInset : 0)
                .padding(.bottom, Theme.cardInset)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .presentationDetents([step == 0 ? .fraction(0.8) : .height(max(1, summaryHeight + footerHeight - ScreenInsets.bottom))])
        .presentationBackground(Theme.groupedBackground)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(showingPaid)
        .sensoryFeedback(.selection, trigger: model.plan)
        .sensoryFeedback(.success, trigger: showingPaid)
        .task(id: showingPaid) {
            guard showingPaid else { return }
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            onPay()
        }
        .animation(.snappy, value: step)
    }

    private var header: some View {
        SheetHeading(
            title: step == 0 ? "Select pricing" : station.venue,
            subtitle: step == 0 ? station.venue : "\(station.kioskLocation) · \(station.id)",
            onClose: showingPaid ? nil : { dismiss() }
        )
        .padding(Theme.cardInset)
    }

    // MARK: Step 1 — every plan readable in full; selected plan gets the dark outline
    private var pricing: some View {
        VStack(spacing: 12) {
            ForEach(plans, id: \.plan) { p in
                Button { model.plan = p.plan } label: { planCard(p, selected: model.plan == p.plan) }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.plan == p.plan ? .isSelected : [])
            }
        }
    }

    private func planCard(_ p: PlanInfo, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.name).font(.headline)
                ViewThatFits(in: .horizontal) {
                    Text("\(p.price) · \(p.max)").lineLimit(1).fixedSize()
                    VStack(alignment: .leading, spacing: 2) { Text(p.price); Text(p.max) }
                }
                .font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(.primary)
            }
            ForEach(p.points, id: \.self) { pt in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark").font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary).frame(width: 20).accessibilityHidden(true)
                    Text(pt).font(.subheadline)
                }
            }
            Text(p.note).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: Theme.cardRadius, style: .circular))
        .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .circular)
                    .strokeBorder(selected ? Color.primary.opacity(0.65) : .clear, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
    }

    // MARK: Step 2 — summary shows the chosen plan again, in full
    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                row(icon: "doc.text") {
                    Text("\(chosen.name) · \(chosen.price)").font(.body.weight(.semibold))
                    Text(([chosen.max] + chosen.points.dropFirst()).joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                    Label { Text(chosen.note) } icon: { AppIcon("exclamationmark.triangle.fill", size: 13).foregroundStyle(.orange) }
                        .font(.subheadline.weight(.medium)).foregroundStyle(Color(red: 0.36, green: 0.24, blue: 0))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1), in: .rect(cornerRadius: 12, style: .circular)).padding(.top, 4)
                } action: { step = 0 }
                Divider().padding(.leading, 66)
                if let promo {
                    row(icon: "tag.fill", tint: Theme.success) {
                        Text("\(promo) applied").font(.body.weight(.semibold))
                        Text("First 30 min free").font(.subheadline).foregroundStyle(.secondary)
                    } action: { self.promo = nil }
                } else if promoEditing {
                    HStack(spacing: 14) {
                        icon("tag.fill")
                        TextField("Promo code", text: $promoText).textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .font(.system(.body, design: .rounded).weight(.semibold)).onSubmit(applyPromo)
                        Button("Apply", action: applyPromo).buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.small)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                } else {
                    row(icon: "tag.fill") { Text("Add promo code").font(.body.weight(.semibold)) } action: { promoEditing = true }
                }
                Divider().padding(.leading, 66)
                if pickPay {
                    ForEach(model.paymentMethods) { m in
                        Button { model.defaultPaymentID = m.id; pickPay = false } label: {
                            HStack(spacing: 14) {
                                icon(m.systemImage)
                                Text(m.title).foregroundStyle(.primary)
                                Spacer()
                                if m.id == model.defaultPayment.id { AppIcon("checkmark", size: 16).foregroundStyle(Theme.brand) }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                        }
                        .disabled(!m.isUsable)
                        .accessibilityAddTraits(m.id == model.defaultPayment.id ? .isSelected : [])
                    }
                } else {
                    row(icon: model.defaultPayment.systemImage) { Text(model.defaultPayment.title).font(.body.weight(.semibold)) } trailing: {
                        Text("Change").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.brand)
                    } action: { pickPay = true }
                }
            }
            .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: Theme.cardRadius, style: .circular))
            Label("\(station.rate.hold.usd) temporary hold, released when you return. " + (mode == .code ? "Your time starts when the charger comes out, not now." : "Not a charge."), symbol: "lock.fill")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        let showApplePay = step == 1 && !showingPaid && model.defaultPayment.kind == .applePay
        return ZStack {
            // Mount during pricing so PassKit is ready before the summary appears.
            CheckoutApplePayButton(type: mode == .code ? .checkout : .rent, action: confirmPayment)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.buttonHeight)
                .opacity(showApplePay ? 1 : 0)
                .allowsHitTesting(showApplePay)
                .accessibilityHidden(!showApplePay)
                .transaction { $0.animation = nil }

            if step == 0 {
                PrimaryButton(title: "Continue") { step = 1 }
            } else if showingPaid {
                Label("Paid", systemImage: "checkmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
                    .background(Theme.ink, in: .capsule)
                    .transition(reduceMotion ? .identity : .scale(scale: 0.96).combined(with: .opacity))
            } else if !showApplePay {
                PrimaryButton(title: mode == .code ? "Pay now" : "Rent charger", action: confirmPayment)
            }
        }
    }

    private func confirmPayment() {
        if model.isDemo, mode == .code {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showingPaid = true }
        } else {
            onPay()
        }
    }

    private func applyPromo() {
        let v = promoText.trimmingCharacters(in: .whitespaces).uppercased()
        guard !v.isEmpty else { return }
        promo = v; promoEditing = false
    }

    private func icon(_ name: String, tint: Color = .primary) -> some View {
        AppIcon(name, size: 20).foregroundStyle(tint).frame(width: 36, height: 36)
            .background(tint == .primary ? Color(uiColor: .secondarySystemBackground) : tint.opacity(0.14), in: .rect(cornerRadius: Theme.iconTileRadius, style: .circular))
    }

    private func row<C: View>(icon name: String, tint: Color = .primary, @ViewBuilder content: () -> C, action: @escaping () -> Void) -> some View {
        row(icon: name, tint: tint, content: content, trailing: { AppIcon("chevron.right", size: 13).foregroundStyle(Theme.brand) }, action: action)
    }
    private func row<C: View, T: View>(icon name: String, tint: Color = .primary, @ViewBuilder content: () -> C, @ViewBuilder trailing: () -> T, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {   // icon + chevron line up with the heading
                icon(name, tint: tint).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
                VStack(alignment: .leading, spacing: 3) { content() }.frame(maxWidth: .infinity, alignment: .leading)
                trailing().alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Apple's empty-battery look: grey outline, short red fill — for "Phone about to die?"
struct LowBatteryIcon: View {
    @State private var dim = false
    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).stroke(.primary.opacity(0.4), lineWidth: 1.5).frame(width: 26, height: 14)
                RoundedRectangle(cornerRadius: 1.6).fill(Color(red: 1, green: 0.23, blue: 0.19)).frame(width: 4.5, height: 9)
                    .padding(.leading, 2.5).opacity(dim ? 0.35 : 1)
            }
            RoundedRectangle(cornerRadius: 1).fill(.primary.opacity(0.4)).frame(width: 2, height: 5.5)
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { dim = true } }
        .accessibilityHidden(true)
    }
}
