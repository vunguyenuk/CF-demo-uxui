import SwiftUI
import MapKit

struct StationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let station: Station
    @State private var appeared = false

    private var live: Station { model.stations.first { $0.id == station.id } ?? station }

    var body: some View {
        FittedActionSheet {
            VStack(alignment: .leading, spacing: 16) {
                header
                facts
                actions
            }
            .padding(Theme.cardInset)
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) { appeared = true } }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(live.venue).font(.headline).accessibilityAddTraits(.isHeader)
                Text("\(live.kioskLocation) · \(model.walkMinutes(live)) min walk").font(.subheadline).foregroundStyle(.secondary)
                statusBadge.padding(.top, 6)
            }
            Spacer(minLength: 0)
            Image("KioskHero")
                .resizable().scaledToFit()
                .frame(height: 96)
                .rotation3DEffect(.degrees(appeared ? 0 : -25), axis: (0, 1, 0))
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var statusBadge: some View {
        switch live.pinKind {
        case .ready:
            Label("Open · \(live.hours.replacingOccurrences(of: "Open ", with: ""))", symbol: "circle.fill").labelStyle(BadgeLabel(color: Theme.success))
        case .empty:
            Label("No chargers right now · returns OK", symbol: "circle.fill").labelStyle(BadgeLabel(color: Theme.warning))
        case .offline:
            Label("Station offline", symbol: "circle.fill").labelStyle(BadgeLabel(color: Theme.offline))
        }
    }

    /// Three numbers, nothing to read: chargers, free slots, price.
    private var facts: some View {
        HStack(spacing: 0) {
            fact("\(live.chargers)", "chargers")
            Divider().frame(height: 40)
            fact("\(live.returnSlots)", "free slots")
            Divider().frame(height: 40)
            fact(live.rate.pricePerBlock.usd.replacingOccurrences(of: ".00", with: ""), "per \(live.rate.blockLabel)")
        }
        .padding(.vertical, 14)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: Theme.groupRadius, style: .circular))
    }

    private func fact(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).bigNumber(26).contentTransition(.numericText())
            Text(l).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var tiles: some View {
        HStack(spacing: 10) {
            tile(value: live.chargers, label: "Chargers ready", icon: "battery.100percent.bolt", tint: Theme.brand)
            tile(value: live.returnSlots, label: "Free return slots", icon: "arrow.down.to.line", tint: Theme.success)
        }
    }

    private func tile(value: Int, label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).foregroundStyle(tint).font(.headline)
            Text("\(value)").bigNumber(30).contentTransition(.numericText(value: Double(value)))
            Text(label).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: Theme.optionRadius, style: .circular))
        .animation(.spring, value: value)
    }

    /// Price in plain words before anything is rented (painpoint P2).
    private var priceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What you'll pay").font(.headline)
            Text(live.rate.headline).bigNumber(24)
            HStack(spacing: 8) {
                ForEach(live.rate.examples, id: \.label) { ex in
                    VStack(spacing: 2) {
                        Text(ex.price.usd).font(.system(.headline, design: .rounded)).monospacedDigit()
                        Text(ex.label).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 12))
                }
            }
            Label("Each started \(live.rate.blockLabel) is billed in full. Never more than \(live.rate.dailyMax.usd) a day\(live.rate.taxNote.map { ", \($0)" } ?? "").", symbol: "checkmark.circle.fill")
            Label("A \(live.rate.hold.usd) hold is released after you return. It's not a charge.", symbol: "lock.open.fill")
            Label("Not returned within \(Int(live.rate.nonReturnHours)) hours: \(live.rate.nonReturnFee.usd).", symbol: "exclamationmark.circle.fill")
        }
        .font(.footnote)
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.primary)
        .cardStyle()
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
                model.directionsTo = live
            } label: {
                Label("Walk", symbol: "figure.walk")
                    .font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity).frame(height: Theme.buttonHeight)
                    .background(Theme.brandSoft, in: .capsule)
            }
            .buttonStyle(.plain)

            Button {
                dismiss()
                if model.activeRental != nil { model.startReturnFlow() } else { model.startRentFlow(at: live) }
            } label: {
                Label(model.activeRental != nil ? "Return here" : "Scan to rent",
                      symbol: model.activeRental != nil ? "arrow.down.to.line" : "qrcode.viewfinder")
                    .font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity).frame(height: Theme.buttonHeight)
            }
            .buttonStyle(FilledCapsuleStyle(tint: Theme.brand))
            .disabled(model.activeRental == nil ? live.chargers == 0 || live.status == .offline : live.returnSlots == 0)
        }
    }
}

struct BadgeLabel: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
            configuration.title.font(.footnote.weight(.semibold)).foregroundStyle(color)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.12), in: .capsule)
    }
}

/// Tapping search suggests the closest station first; one tap starts directions.
struct NearestStationSheet: View {
    @Environment(AppModel.self) private var model
    var onGo: (Station) -> Void

    private var renting: Bool { model.activeRental != nil }
    private var list: [Station] {
        model.stations.filter { $0.status == .online && (renting ? $0.returnSlots > 0 : $0.chargers > 0) }
            .sorted { model.distance(to: $0) < model.distance(to: $1) }
    }

    var body: some View {
        if let c = list.first {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.venue).font(.title2.bold())
                        Text(c.kioskLocation).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            chip("\(model.walkMinutes(c)) min", Theme.success)
                            chip(renting ? "\(c.returnSlots) free slots" : "\(c.chargers) chargers", .secondary)
                        }
                    }
                    Spacer()
                    Image("KioskHero").resizable().scaledToFit().frame(height: 80)
                }
                Button { onGo(c) } label: {
                    Label("Directions · \(model.walkMinutes(c)) min", symbol: "location.fill").font(.headline).frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
                }
                .buttonStyle(FilledCapsuleStyle(tint: Theme.brand))
                Text("Also nearby").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(Array(list.dropFirst().prefix(3).enumerated()), id: \.element.id) { i, s in
                        if i > 0 { Divider().padding(.leading, 16) }
                        Button { onGo(s) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.venue).font(.body.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
                                    Text("\(renting ? "\(s.returnSlots) free slots" : "\(s.chargers) chargers") · \(model.walkMinutes(s)) min")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                AppIcon("location.fill", size: 17).foregroundStyle(Theme.brand)
                                    .frame(width: 38, height: 38).background(Theme.brandSoft, in: .circle)
                            }
                            .padding(.horizontal, 16).frame(minHeight: 58).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: Theme.groupRadius, style: .circular))
            }
            .padding(20)
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.footnote.weight(.semibold)).foregroundStyle(c)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(c.opacity(0.12), in: .capsule)
    }
}
