import SwiftUI
import CoreLocation

/// The old app's 2D logo on white. No 3D intro: people opening this app are usually low on battery.
struct LogoSplashView: View {
    var onFinish: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Image("Wordmark").resizable().scaledToFit().frame(width: 212)
                .opacity(shown ? 1 : 0).scaleEffect(shown ? 1 : 0.96)
        }
        .task {
            withAnimation(.smooth(duration: 0.5)) { shown = true }
            try? await Task.sleep(for: .seconds(1.1))
            onFinish()
        }
    }
}

/// Phone number only (no Google: a phone lets us reach people who don't return a charger, the SMS code autofills,
/// and emails are too easy to farm for promos). Shown at checkout, not at launch.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var askCode = false
    @State private var code = ""
    @State private var wrong = false
    @State private var resend = 30
    var onVerified: () -> Void = {}
    private enum Field: Hashable { case phone, verification }
    @FocusState private var focus: Field?

    private var digits: String { number.filter(\.isNumber) }

    var body: some View {
        FittedActionSheet(background: Color(uiColor: .systemBackground)) {
            VStack(alignment: .leading, spacing: 0) {
                if askCode { codeStep } else { phoneStep }
            }
            .padding(Theme.cardInset)
        }
        .animation(.smooth(duration: 0.35), value: askCode)
        .task(id: askCode) {
            await Task.yield()
            focus = askCode ? .verification : .phone
        }
    }

    private func header(_ title: String, _ sub: String) -> some View {
        SheetHeading(title: title, subtitle: sub, onClose: { dismiss() })
    }

    private var phoneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Sign in to rent", "One text message. Takes 10 seconds.")
            // one field like the web: "US +1" prefix + the number
            HStack(spacing: 10) {
                Text("US +1").font(.body.weight(.medium)).foregroundStyle(.secondary)
                    .accessibilityLabel("United States, plus one")
                TextField("(213) 555-0142", text: $number)
                    .keyboardType(.phonePad).textContentType(.telephoneNumber).focused($focus, equals: .phone).font(.body)
                    .accessibilityLabel("Phone number")
                    .onChange(of: number) { _, v in number = Self.format(v) }
            }
            .padding(.horizontal, 16).frame(height: Theme.buttonHeight)
            .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: Theme.fieldRadius, style: .circular))   // visible on the white sheet
            Label { Text("We use your number to reach you about a rental, never for marketing.") }
                icon: { AppIcon("lock.fill", size: 13) }
                .font(.footnote).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                PrimaryButton(title: "Text me a code") { model.sendSignInCode(to: "+1 \(number)"); askCode = true }
                    .disabled(digits.count != 10)
                Button("Use the demo number") { number = Self.format("2135550142") }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.brand)
                    .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            }
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Enter the code", "Sent to +1 \(number)")
            ZStack {
                // One hidden field drives the 4 boxes; .oneTimeCode lets iOS fill it from Messages
                TextField("", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .focused($focus, equals: .verification).opacity(0.01)
                    .accessibilityLabel("Four-digit verification code")
                    .onChange(of: code) { _, input in
                        let digits = String(input.filter(\.isNumber).prefix(4))
                        if digits != input { code = digits }
                        guard !digits.isEmpty else { return }
                        wrong = false
                        guard digits.count == 4 else { return }
                        Task {
                            if await model.verifySignIn(phone: "+1 \(number)", code: digits) {
                                focus = nil
                                onVerified()
                            } else {
                                wrong = true
                                code = ""
                            }
                        }
                    }
                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { i in
                        let ch = i < code.count ? String(Array(code)[i]) : ""
                        Text(ch).font(.system(size: 26, weight: .bold, design: .rounded))
                            .frame(maxWidth: 58, minHeight: 64)
                            .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: Theme.fieldRadius, style: .circular))
                            .overlay(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .circular).strokeBorder(i == code.count ? Theme.brand : .clear, lineWidth: 1.5))
                    }
                }
                .allowsHitTesting(false).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .onTapGesture { focus = .verification }
            // what iOS shows above the keyboard when the SMS arrives (demo: tap to fill)
            if code.isEmpty {
                Button { code = "1234" } label: {
                    VStack(spacing: 1) {
                        Text("From Messages").font(.caption).foregroundStyle(.secondary)
                        Text("1234").font(.system(size: 17, weight: .semibold, design: .rounded)).tracking(2)
                    }
                    .padding(.horizontal, 16).frame(height: 48)
                    .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 12, style: .circular))
                }
                .buttonStyle(.plain).frame(maxWidth: .infinity)
            }
            if wrong {
                Text("That code isn't right. Try 1234 in the demo.")
                    .font(.subheadline).foregroundStyle(Theme.danger)
            }
            if resend > 0 {
                Text("Resend code in 0:\(String(format: "%02d", resend))")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Button("Resend code") { resend = 30; code = ""; wrong = false; focus = .verification }
            }
        }
        .task(id: resend > 0) {
            while resend > 0 {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                resend -= 1
            }
        }
    }

    static func format(_ v: String) -> String {
        let d = String(v.filter(\.isNumber).prefix(10))
        switch d.count {
        case 0...3: return d
        case 4...6: return "(\(d.prefix(3))) \(d.dropFirst(3))"
        default: return "(\(d.prefix(3))) \(d.dropFirst(3).prefix(3))-\(d.dropFirst(6))"
        }
    }
}

/// Asks for location with the system (iOS 26) alert, then hands over to the map.
@MainActor
final class LocationPermission: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var done: (() -> Void)?
    func request(_ done: @escaping () -> Void) {
        self.done = done
        manager.delegate = self
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() } else { done() }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let status = m.authorizationStatus   // read here; don't send the manager into the task
        Task { @MainActor in
            if status != .notDetermined { self.done?(); self.done = nil }
        }
    }
}

struct LocationStepView: View {
    @Environment(AppModel.self) private var model
    @State private var perm = LocationPermission()

    var body: some View {
        NearbyHomeView(mode: .rent).blur(radius: 6).allowsHitTesting(false)
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                perm.request { withAnimation(.smooth) { model.completeLocation() } }
            }
    }
}
