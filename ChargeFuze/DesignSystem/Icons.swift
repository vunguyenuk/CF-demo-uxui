import SwiftUI

/// App icons = SF Symbols (iOS 26/27), semibold, following Dynamic Type. `AppIcon` for a sized glyph,
/// `Label(_:symbol:)` for a label that uses it.
struct AppIcon: View {
    let name: String
    var size: CGFloat? = nil
    @ScaledMetric(relativeTo: .body) private var base: CGFloat = 20
    init(_ name: String, size: CGFloat? = nil) { self.name = name; self.size = size }
    var body: some View {
        let s = size ?? base
        Image(systemName: name)
            .font(.system(size: s * 0.96, weight: .semibold))   // semibold reads modern and matches .headline
            .frame(width: s, height: s)
    }
}

extension Label where Title == Text, Icon == AppIcon {
    init(_ titleKey: LocalizedStringKey, symbol name: String) {
        self.init { Text(titleKey) } icon: { AppIcon(name) }
    }
    init<S: StringProtocol>(_ title: S, symbol name: String) {
        self.init { Text(title) } icon: { AppIcon(name) }
    }
}
