import SwiftUI

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showSignIn = false
    @State private var promo = ""
    @State private var promoResult: Bool?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Text(String(model.userName.prefix(1)) + String(model.userName.split(separator: " ").last?.prefix(1) ?? ""))
                            .font(.title3.bold()).foregroundStyle(Theme.ink)
                            .frame(width: 56, height: 56).background(Theme.brandSoft, in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.userName).font(.headline)
                            Text(model.phone).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Activity") {
                    NavigationLink { RentalsView(mode: 0) } label: { Label("Rentals", symbol: "clock.arrow.circlepath") }
                    NavigationLink { RentalsView(mode: 1) } label: {
                        LabeledContent { Text("holds & charges") } label: { Label("Money activity", symbol: "creditcard.fill") }
                    }
                }

                Section("Wallet") {
                    NavigationLink { PaymentMethodsView() } label: {
                        LabeledContent { Text(model.defaultPayment.title) } label: { Label("Payment", symbol: "creditcard.fill") }
                    }
                    LabeledContent {
                        Text((model.promoCredit).usd)
                    } label: { Label("FUZE Cash", symbol: "bolt.circle.fill") }
                    NavigationLink { PassView() } label: {
                        LabeledContent { Text(model.pass == nil ? "None" : "Active") } label: { Label("Rental Pass", symbol: "ticket.fill") }
                    }
                    HStack {
                        TextField("Promo code", text: $promo).textInputAutocapitalization(.characters)
                        Button("Apply") {
                            Task { promoResult = await model.applyPromo(promo); if promoResult == true { promo = "" } }
                        }
                        .disabled(promo.isEmpty)
                    }
                    if let promoResult {
                        Text(promoResult ? "Added $2.00 to FUZE Cash" : "That code isn't valid")
                            .font(.footnote).foregroundStyle(promoResult ? Theme.success : Theme.danger)
                    }
                }

                Section {
                    ShareLink(item: URL(string: "https://www.chargefuze.com")!,
                              message: Text("Join me on chargeFUZE! Use my link and we both get a free rental.")) {
                        Label("Invite friends", symbol: "gift.fill")
                    }
                }

                Section {
                    Toggle(isOn: $model.remindersOn) { Label("Return reminders", symbol: "bell.badge.fill") }
                    Toggle(isOn: $model.nearbyAlertsOn) { Label("Low-battery station alerts", symbol: "location.fill") }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("We remind you 5 minutes before each new block, before the daily max, before the venue closes, and 2 hours before the return deadline.")
                }

                if model.isDemo {   // demo switches: hidden when the live API is on
                Section {
                    Toggle("Kiosk won't release a charger", isOn: $model.demoKioskWontRelease)
                    Toggle("Charger not pulled out yet", isOn: $model.demoChargerNotTaken)
                    Toggle("Return isn't confirmed by kiosk", isOn: $model.demoReturnNotConfirmed)
                    Toggle("Show low-battery banner", isOn: $model.demoLowBattery)
                    if model.activeRental != nil {
                        Button("Fast-forward rental by 1 hour") { model.fastForward(hours: 1) }
                    }
                    Button("Replay How it works") { model.replayOnboarding() }
                } header: {
                    Text("Demo")
                } footer: {
                    Text("Demo build only. Use these to show each case to the client.")
                }
                }

                Section {
                    Link("Privacy Policy", destination: URL(string: "https://www.chargefuze.com/privacy")!)
                    Link("Terms of Service", destination: URL(string: "https://www.chargefuze.com/terms")!)
                    if model.signedIn {
                        Button("Sign out", role: .destructive) { model.signOut(); dismiss() }
                    } else {
                        Button("Sign in") { showSignIn = true }
                    }
                }
            }
            .navigationTitle("Account")
            .sheet(isPresented: $showSignIn) {
                SignInView { showSignIn = false }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
            .navigationDestination(isPresented: $model.showRentalsInAccount) { RentalsView(mode: 0) }
        }
    }
}

struct PaymentMethodsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        List {
            Section {
                ForEach(model.paymentMethods) { pm in
                    Button { if pm.isUsable { model.defaultPaymentID = pm.id } } label: {
                        HStack {
                            Image(systemName: pm.systemImage).frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(pm.title).foregroundStyle(.primary)
                                if let s = pm.subtitle { Text(s).font(.footnote).foregroundStyle(pm.isUsable ? Color.secondary : Theme.danger) }
                            }
                            Spacer()
                            if model.defaultPaymentID == pm.id { Image(systemName: "checkmark").foregroundStyle(Theme.brand) }
                        }
                    }
                    .disabled(!pm.isUsable)
                    .accessibilityAddTraits(model.defaultPaymentID == pm.id ? .isSelected : [])
                }
            } footer: {
                Text("The default is preselected when you rent. You can switch for any rental.")
            }
        }
        .navigationTitle("Payment")
        .sensoryFeedback(.selection, trigger: model.defaultPaymentID)
    }
}

/// Festival pass, explained before purchase and counted down after (r/bonnaroo).
struct PassView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            if let p = model.pass {
                Section {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(p.name).font(.headline)
                            Text(max(0, p.endsAt.timeIntervalSince(ctx.date)).clock).bigNumber(36)
                            Text("left · ends \(p.endsAt.shortDay), \(p.endsAt.shortTime)").font(.subheadline).foregroundStyle(.secondary)
                            Text(p.note).font(.footnote)
                        }
                    }
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Festival Pass").font(.title3.bold())
                        Text("$60 + tax for 48 hours of unlimited swaps at one festival.")
                        Label("One charge only, shown as FUZE TECHNOLOGY", symbol: "checkmark.circle.fill")
                        Label("A countdown shows when your pass ends", symbol: "checkmark.circle.fill")
                        Label("Return your last charger before it ends, or before the area closes", symbol: "checkmark.circle.fill")
                    }
                    .font(.subheadline)
                    Button("Buy at Crypto.com Arena (demo)") {
                        if let s = model.stations.first(where: { $0.rate == .festival }) { model.buyFestivalPass(at: s) }
                    }
                }
            }
        }
        .navigationTitle("Rental Pass")
    }
}
