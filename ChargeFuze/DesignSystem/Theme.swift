import SwiftUI

enum Theme {
    /// chargeFUZE brand blue (Figma logo #0080F6).
    static let brand = Color(red: 0.0, green: 0.502, blue: 0.965)
    /// Soft fill behind icons/boxes. Neutral grey (was a light blue): blue is kept for the one main action per screen.
    static let brandSoft = Color.primary.opacity(0.06)
    static let ink = Color(red: 0.06, green: 0.07, blue: 0.09)
    /// Shared height for capsule and round controls.
    static let buttonHeight: CGFloat = 46
    static let iconButton: CGFloat = buttonHeight
    /// Inner padding of every bottom card / sheet (same as the kiosk list sheet).
    static let cardInset: CGFloat = 16
    // Corner radii from the web prototype, expressed in points for SwiftUI.
    static let iconTileRadius: CGFloat = 11
    static let fieldRadius: CGFloat = 16
    static let rowRadius: CGFloat = 16
    static let optionRadius: CGFloat = 18
    static let noticeRadius: CGFloat = 20
    static let cardRadius: CGFloat = 22
    static let groupRadius: CGFloat = 26
    static let turnCardRadius: CGFloat = 30
    static let sheetRadius: CGFloat = 34
    static let walkCardRadius: CGFloat = 38
    static let kioskCodeSheetRadius: CGFloat = 46
    static let success = Color(red: 0.13, green: 0.70, blue: 0.36)
    static let warning = Color(red: 0.93, green: 0.55, blue: 0.06)
    static let danger = Color(red: 0.92, green: 0.23, blue: 0.20)
    static let offline = Color(white: 0.62)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)

    static let usd: FloatingPointFormatStyle<Double>.Currency =
        .currency(code: "USD").locale(Locale(identifier: "en_US"))
}

extension Double {
    /// Always US-style money ("$1.99"), whatever the phone's region is.
    var usd: String { formatted(Theme.usd) }
}

extension Date {
    var shortTime: String {
        formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "en_US")))
    }
    var shortDay: String {
        formatted(Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day().locale(Locale(identifier: "en_US")))
    }
}

extension TimeInterval {
    /// 0:42 · 1:05:09
    var clock: String {
        let s = Int(self.rounded(.down))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
    /// "1 h 10 min" · "42 min"
    var friendly: String {
        let m = Int(self / 60)
        if m < 60 { return "\(max(m, 1)) min" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h) h" : "\(h) h \(r) min"
    }
}

/// Big rounded numbers used for money and timers.
struct BigNumber: ViewModifier {
    var size: CGFloat
    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
    }
}

extension View {
    func bigNumber(_ size: CGFloat = 34) -> some View { modifier(BigNumber(size: size)) }

    /// A white rounded card used across the app.
    func cardStyle(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Theme.card, in: .rect(cornerRadius: Theme.cardRadius, style: .circular))
    }
}

/// The chargeFUZE bolt mark (from the Figma logo).
struct BoltMark: View {
    var size: CGFloat = 28
    var body: some View {
        Image("BoltMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
