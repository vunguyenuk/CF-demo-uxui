import SwiftUI

@main
struct ChargeFuzeApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.brand)
                .preferredColorScheme(.light)
                .environment(\.services, model.services)
                .task { await model.refreshNearby(); await model.refreshAccount() }
                .onOpenURL { model.handle(url: $0) }
                .onChange(of: model.activeRental != nil) { _, renting in
                    if renting { model.endLowBatteryActivity(); model.startRentalActivity() } else { model.endRentalActivity() }
                }
        }
        // Low battery lives outside the app: start the Live Activity as the user leaves.
        .onChange(of: phase) { _, p in
            if p == .background, model.signedIn { model.updateLowBatteryActivity(); model.refreshRentalActivity() }
            if p == .active { model.endLowBatteryActivity() }
        }
    }
}

/// 2D logo → location (system alert) → nearest kiosks. No sign-in until checkout (phone only).
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var splashDone = false

    var body: some View {
        ZStack {
            if splashDone {
                // No sign-in to look around: splash → location → map. Sign-in happens at checkout.
                if !model.locationAsked { LocationStepView().transition(.opacity) }
                else { HomeContainer().transition(.opacity) }
            }
            if !splashDone {
                LogoSplashView { withAnimation(.easeInOut(duration: 0.35)) { splashDone = true } }
                    .transition(.opacity).zIndex(10)
            }
        }
        #if DEBUG
        .task {
            // QA: `-demo <screen>` skips splash + location and opens that screen (see AppModel.runDemo)
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-demo"), i + 1 < args.count {
                splashDone = true; model.completeLocation()
                try? await Task.sleep(for: .milliseconds(700))
                model.runDemo(args[i + 1])
            }
        }
        #endif
        .animation(.smooth(duration: 0.4), value: model.signedIn)
        .animation(.smooth(duration: 0.4), value: model.locationAsked)
    }
}
