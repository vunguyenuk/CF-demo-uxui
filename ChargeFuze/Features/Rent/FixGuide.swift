import SwiftUI

/// Visual fix guides by error type (instead of sending people to the chatbot).
enum FixKind: String, Identifiable {
    case noEject, wontInsert, notCharging
    var id: String { rawValue }

    var title: String {
        switch self { case .noEject: "No charger came out"; case .wontInsert: "Won't go in?"; case .notCharging: "Not charging?" }
    }
    var subtitle: String {
        switch self {
        case .noEject: "You haven't been charged. Try this first:"
        case .wontInsert: "Most of the time it's facing the wrong way."
        case .notCharging: "Try these two checks first."
        }
    }
    var steps: [(icon: String, title: String, detail: String)] {
        switch self {
        case .noEject: [("clock.fill", "Wait 5 seconds", "The slot light starts blinking blue"),
                        ("arrow.down", "Pull the blinking one", "Straight out, firmly"),
                        ("arrow.clockwise", "Still stuck?", "We release a different charger")]
        case .wontInsert: [("bolt.fill", "Logo facing you", "The blue bolt on the front looks at you"),
                           ("arrow.down", "Cable end goes in first", "The end with the 3 cables"),
                           ("checkmark", "Push until it clicks", "The slot light turns green")]
        case .notCharging: [("powerplug.fill", "Plug it all the way in", "Until the cable boot touches your phone"),
                            ("bolt.fill", "Press the blue Power On button", "On the side of the charger"),
                            ("arrow.clockwise", "Still nothing?", "Swap it at any kiosk, faulty time is free")]
        }
    }
    var primary: String { switch self { case .noEject: "Release another charger"; case .wontInsert: "Got it"; case .notCharging: "Swap it" } }
    var secondary: String { switch self { case .noEject: "Cancel · no charge"; case .wontInsert: "Try another empty slot"; case .notCharging: "It's charging now" } }
}

struct FixGuideView: View {
    let kind: FixKind
    var onPrimary: () -> Void = {}
    var onSecondary: () -> Void = {}
    var onClose: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        if kind == .notCharging { chargingGuide } else { standardGuide }
    }

    private var chargingGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image("Charger3D").resizable().scaledToFit()
                    .frame(width: 52, height: 64)
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 3)
                    .accessibilityHidden(true)
                SheetHeading(title: kind.title, subtitle: kind.subtitle, onClose: onClose)
            }

            VStack(spacing: 0) {
                ForEach(Array(kind.steps.prefix(2).enumerated()), id: \.offset) { index, step in
                    if index > 0 { Divider().padding(.leading, 58) }
                    HStack(spacing: 12) {
                        AppIcon(step.icon, size: 18)
                            .frame(width: 34, height: 34)
                            .background(Theme.brandSoft, in: .rect(cornerRadius: Theme.iconTileRadius))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).font(.subheadline.weight(.semibold))
                            Text(step.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .opacity(reduceMotion || shown ? 1 : 0)
                    .offset(y: reduceMotion || shown ? 0 : 6)
                    .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.06), value: shown)
                }
            }
            .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: Theme.cardRadius, style: .circular))

            VStack(spacing: 4) {
                Button(kind.secondary, action: onSecondary)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
                PrimaryButton(title: kind.primary, action: onPrimary)
            }
        }
        .padding(Theme.cardInset)
        .onAppear { shown = true }
    }

    private var standardGuide: some View {
        VStack(spacing: 16) {
            Image("Kiosk3D").resizable().scaledToFit().frame(height: 96).shadow(color: .black.opacity(0.18), radius: 6, y: 6)
            VStack(spacing: 6) {
                Text(kind.title).font(.headline)
                Text(kind.subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                ForEach(Array(kind.steps.enumerated()), id: \.offset) { i, st in
                    HStack(spacing: 14) {
                        Text("\(i + 1)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Color.primary, in: .circle)
                        AppIcon(st.icon, size: 22).foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44).background(Theme.brandSoft, in: .rect(cornerRadius: 13, style: .circular))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(st.title).font(.headline)
                            Text(st.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: Theme.optionRadius, style: .circular))
                    .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 8)
                    .animation(.easeOut(duration: 0.35).delay(Double(i) * 0.09), value: shown)
                }
            }
            PrimaryButton(title: kind.primary) { onPrimary() }.padding(.top, 4)
            Button(kind.secondary) { onSecondary() }
                .font(.headline).frame(minHeight: Theme.buttonHeight)
        }
        .padding(Theme.cardInset)
        .onAppear { shown = true }
    }
}

/// Sheet wrapper for FixGuideView.
struct FixGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let kind: FixKind
    var onPrimary: () -> Void = {}
    var onSecondary: () -> Void = {}
    var body: some View {
        FittedActionSheet {
            FixGuideView(kind: kind,
                         onPrimary: { dismiss(); onPrimary() },
                         onSecondary: { dismiss(); onSecondary() },
                         onClose: { dismiss() })
        }
    }
}
