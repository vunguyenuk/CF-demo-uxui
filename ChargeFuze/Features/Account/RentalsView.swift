import SwiftUI
import MapKit

struct RentalsView: View {
    @Environment(AppModel.self) private var model
    @State var mode = 0   // 0 rentals · 1 money activity

    var body: some View {
        Group {
            List {
                Section {
                    Picker("View", selection: $mode) {
                        Text("Rentals").tag(0)
                        Text("Money activity").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if mode == 0 { rentals } else { money }
            }
            .navigationTitle("Rentals")
            .navigationDestination(for: RentalRecord.self) { RentalDetailView(record: $0) }
            .animation(.smooth, value: mode)
        }
    }

    @ViewBuilder private var rentals: some View {
        if model.history.isEmpty {
            ContentUnavailableView {
                Label("No rentals yet", symbol: "bolt.slash")
            } description: {
                Text("Rent a charger at any chargeFUZE station and it shows up here.")
            }
        } else {
            Section {
                ForEach(model.history) { r in
                    NavigationLink(value: r) {
                        HStack(spacing: 12) {
                            Image(systemName: "bolt.fill").foregroundStyle(Theme.ink)
                                .frame(width: 34, height: 34).background(Theme.brandSoft, in: .rect(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(r.pickup.venue) → \(r.dropoff.venue)").font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text("\(r.startedAt.shortDay) · \(r.duration.friendly)").font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(r.total.usd).font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    /// S5: every hold, charge and release, in words, matching the card statement.
    @ViewBuilder private var money: some View {
        Section {
            ForEach(model.ledger) { line in LedgerRow(line: line) }
        } header: {
            Text("Shows on your statement as FUZE TECHNOLOGY")
        } footer: {
            Text("A hold is not a charge. It's released when you return the charger; banks can take up to 5 business days to remove it from your statement.")
        }
    }
}

struct LedgerRow: View {
    let line: ChargeLine
    var color: Color {
        switch line.state { case .posted: .primary; case .pending: Theme.warning; case .released, .refunded: Theme.success }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: line.systemImage).foregroundStyle(color).frame(width: 22)
                Text(line.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(line.amount.usd).font(.subheadline.weight(.semibold)).monospacedDigit()
                    .strikethrough(line.state == .released || line.state == .refunded)
                    .foregroundStyle(color)
            }
            HStack {
                Text(line.state.rawValue).font(.footnote.weight(.bold)).foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 2).background(color.opacity(0.12), in: .capsule)
                Text(line.date.shortDay).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.leading, 32)
            Text(line.detail).font(.footnote).foregroundStyle(.secondary).padding(.leading, 32)
        }
        .padding(.vertical, 4)
    }
}

struct RentalDetailView: View {
    @Environment(AppModel.self) private var model
    let record: RentalRecord

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.total.usd).font(.largeTitle.bold().monospacedDigit())
                    Text("\(record.startedAt.shortDay) · \(record.duration.friendly)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Section {
                Map(initialPosition: .automatic, interactionModes: []) {
                    Marker(record.pickup.venue, systemImage: "bolt.fill", coordinate: record.pickup.coordinate).tint(Theme.success)
                    Marker(record.dropoff.venue, systemImage: "arrow.down.to.line", coordinate: record.dropoff.coordinate).tint(Theme.brand)
                }
                .frame(height: 180)
                .listRowInsets(EdgeInsets())
            }
            Section("Proof of return") {
                InfoRow(label: "Picked up", value: "\(record.pickup.venue)\n\(record.startedAt.shortTime)")
                InfoRow(label: "Returned", value: "\(record.dropoff.venue)\n\(record.endedAt.shortTime)")
                InfoRow(label: "Rental ID", value: record.id)
            }
            Section("Charges") {
                ForEach(model.lines(for: record.id)) { LedgerRow(line: $0) }
            }
            Section {
                Button {
                    model.showAccount = false
                    Task { try? await Task.sleep(for: .milliseconds(350)); model.showHelp = true }
                } label: {
                    Label("Ask the assistant about this rental", symbol: "sparkles")
                }
            }
        }
        .navigationTitle("Rental")
        .navigationBarTitleDisplayMode(.inline)
    }
}
