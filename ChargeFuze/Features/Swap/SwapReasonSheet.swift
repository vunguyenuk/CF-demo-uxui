import SwiftUI
import CoreLocation

/// When does a swap happen?
/// 1) "Charger not working?" in the rental card → pick what's wrong;
/// 2) the app notices the phone isn't charging (battery state stays unplugged ~2 min after pickup) → prompt;
/// 3) empty / running low → swap for a full one; 4) hot or swollen → stop using it, swap, no charge.
/// At a kiosk → swap right there. Away from one → walk to the nearest kiosk with a full charger; the faulty time isn't billed.
struct SwapReasonSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pick: Int?

    private let reasons: [(String, String, String)] = [
        ("powerplug.fill", "It's not charging my phone", "Plugged in, but no charging icon"),
        ("exclamationmark.triangle.fill", "Cable or plug is damaged", "Bent, frayed or loose"),
        ("battery.25percent", "It's empty or running low", "Swap it for a full one"),
        ("flame.fill", "It's hot or swollen", "Stop using it now"),
        ("questionmark.bubble.fill", "Something else", "Tell us what happened"),
    ]

    private var pickup: Station? {
        guard let rental = model.activeRental,
              model.swapChargingIssue || rental.elapsed() < 120 else { return nil }
        return model.stations.first { $0.id == rental.station.id }
    }

    private var available: [Station] {
        model.stations.filter { $0.status == .online && $0.chargers > 0 && $0.returnSlots > 0 }
    }

    private var nearest: Station? {
        let origin = pickup?.location ?? model.userLocation
        return available.filter { origin.distance(from: $0.location) < 2_600 }
            .min { origin.distance(from: $0.location) < origin.distance(from: $1.location) }
    }

    private var atKiosk: Station? {
        if let pickup, available.contains(where: { $0.id == pickup.id }) { return pickup }
        return available.filter { model.userLocation.distance(from: $0.location) < 40 }
            .min { model.userLocation.distance(from: $0.location) < model.userLocation.distance(from: $1.location) }
    }

    var body: some View {
        FittedActionSheet {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeading(
                    title: model.swapAuto ? "Your phone isn't charging" : "What's wrong?",
                    subtitle: model.swapAuto ? "No charge for 2 min since you took the charger" : "We'll swap it for a working one",
                    onClose: { dismiss() }
                )
                if !model.swapAuto { reasonList }
                if model.swapAuto || pick != nil { decision }
            }
            .padding(Theme.cardInset)
        }
        .onAppear { if model.swapChargingIssue { pick = 0 } }
        .sensoryFeedback(.selection, trigger: pick)
    }

    private var reasonList: some View {
        VStack(spacing: 0) {
            ForEach(reasons.indices, id: \.self) { i in
                reasonRow(i)
                if i < reasons.count - 1 { Divider().padding(.leading, 66) }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(.rect(cornerRadius: Theme.cardRadius, style: .circular))
    }

    // split out so the type checker stays fast
    private func reasonRow(_ i: Int) -> some View {
        let hot = i == 3
        let iconColor: Color = hot ? .red : .primary
        let tileColor: Color = hot ? Color.red.opacity(0.12) : Color(uiColor: .secondarySystemBackground)
        let selected = pick == i
        return Button {
            if i == 4 { dismiss(); model.showHelp = true } else { withAnimation(.snappy) { pick = i } }
        } label: {
            HStack(spacing: 14) {
                AppIcon(reasons[i].0, size: 18).foregroundStyle(iconColor)
                    .frame(width: 36, height: 36)
                    .background(tileColor, in: .rect(cornerRadius: Theme.iconTileRadius, style: .circular))
                VStack(alignment: .leading, spacing: 2) {
                    Text(reasons[i].1).font(.headline).foregroundStyle(.primary)
                    Text(reasons[i].2).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark" : "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(selected ? Theme.brand : .secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .buttonStyle(SwapReasonRowStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// What we tell the backend (`RentalService.reportIssue`).
    private var reportedReason: String { model.swapAuto ? "not_charging_detected" : pick.map { reasons[$0].1 } ?? "other" }

    @ViewBuilder private var decision: some View {
        if (pick == 0 && !model.swapChargingIssue) || model.swapAuto {   // not charging: try the two quick fixes first
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(FixKind.notCharging.steps.prefix(2).enumerated()), id: \.offset) { i, st in
                    Label { VStack(alignment: .leading) { Text(st.title).font(.headline); Text(st.detail).font(.subheadline).foregroundStyle(.secondary) } }
                        icon: { AppIcon(st.icon, size: 18).foregroundStyle(Theme.brand) }
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: Theme.optionRadius, style: .circular))
        }
        if pick == 3 {
            Label { Text("**Unplug it and stop using it.** Keep it away from your bag. You won't be charged for it.") }
                icon: { AppIcon("exclamationmark.triangle.fill", size: 16).foregroundStyle(.red) }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: .rect(cornerRadius: Theme.optionRadius, style: .circular))
        }
        if let here = atKiosk {
            Label("At \(here.venue)? A replacement and an empty slot are available.", symbol: "mappin")
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: Theme.optionRadius, style: .circular))
            PrimaryButton(title: "Swap here") {
                model.reportChargerIssue(reportedReason)
                dismiss()
                Task { try? await Task.sleep(for: .milliseconds(350)); model.showSwap = true }
            }
        } else if let n = nearest {
            let origin = pickup?.location ?? model.userLocation
            let minutes = max(1, Int((origin.distance(from: n.location) / 80).rounded()))
            Label("Nearest kiosk with a charger and an empty slot: \(n.venue) · about \(minutes) min walk.", symbol: "figure.walk")
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: Theme.optionRadius, style: .circular))
            PrimaryButton(title: "Walk to swap") {
                model.reportChargerIssue(reportedReason)
                model.swapOnArrival = true; dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    model.swapWalkOrigin = origin
                    model.walkTo = n
                }
            }
        } else {
            Label("No nearby kiosk has both a replacement and an empty slot.", systemImage: "info.circle")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        if model.swapAuto {
            Button("It's charging, never mind") { dismiss() }.font(.headline).frame(maxWidth: .infinity)
        }
    }
}

private struct SwapReasonRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(Color.primary.opacity(configuration.isPressed ? 0.06 : 0).allowsHitTesting(false))
            .contentShape(.rect)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
