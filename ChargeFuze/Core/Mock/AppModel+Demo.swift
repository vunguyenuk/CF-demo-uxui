import SwiftUI

// MARK: - Demo / QA only
// Everything here drives the clickable demo (mock services). Live builds never call it:
// the `-demo <screen>` launch argument is DEBUG-only, and the helpers check `isDemo`.

extension AppModel {
    #if DEBUG
    /// Open any screen straight from a launch argument, e.g. `xcrun simctl launch <udid> <bundle> -demo walk`.
    func runDemo(_ name: String) {
        guard let s = nearbyStations.first(where: { $0.status == .online && $0.chargers > 0 }) else { return }
        func rentNow() { demoChargerNotTaken = false; demoKioskWontRelease = false; rentStation = s; pay(); Task { try? await Task.sleep(for: .milliseconds(400)); finishRentFlow() } }
        switch name {
        case "scan": startRentFlow(at: nil)
        case "walk": walkTo = s
        case "walk-signin": signedIn = false; walkTo = s
        case "code": buyUnlockCode(at: s); walkTo = s
        case "arrive": demoArriveNow = true; walkTo = s
        case "signin": signedIn = false; rentStation = s; showPaySheet = true
        case "checkout": rentStation = s; showPaySheet = true
        case "charging": rentStation = s; pay()
        case "eject": demoKioskWontRelease = true; rentStation = s; pay()
        case "renting": rentNow()
        case "rentalsheet": rentNow(); Task { try? await Task.sleep(for: .milliseconds(900)); showRentalSheet = true }
        case "return", "return-unconfirmed", "return-walk", "return-walk-unconfirmed":
            demoReturnNotConfirmed = name.hasSuffix("unconfirmed")
            rentNow()
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                startReturnFlow()
                if name.hasPrefix("return-walk") { walkTo = s }
            }
        case "swap-walk":
            rentNow()
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                swapOnArrival = true
                walkTo = s
            }
        case "swapwhy": rentNow(); Task { try? await Task.sleep(for: .milliseconds(900)); showSwapReasons = true }
        case "notcharging": rentNow(); Task { try? await Task.sleep(for: .milliseconds(1200)); swapAuto = true; notChargingBanner = true }
        case "nextcharge": rentNow(); Task { try? await Task.sleep(for: .milliseconds(300)); activeRental?.startedAt = .now.addingTimeInterval(-26 * 60) }
        case "swap": rentNow(); Task { try? await Task.sleep(for: .milliseconds(900)); showSwap = true }
        default: break
        }
    }
    #endif

    func redeemDemoUnlockCode(at station: Station) {
        guard isDemo, activeRental == nil, unlockCode(for: station) != nil else { return }
        rentStation = station
        pay()
    }

    /// The web keeps the rental and records the replacement when the new charger is taken.
    func completeDemoSwap(rentalID: String, oldSlot: Int, newSlot: Int) {
        guard isDemo, let rental = activeRental, rental.id == rentalID, rental.slot == oldSlot else { return }
        activeRental = Rental(id: rental.id, station: rental.station, slot: newSlot,
                              startedAt: rental.startedAt, payment: rental.payment)
        ledger.insert(ChargeLine(id: "L-" + String(UUID().uuidString.prefix(6)), kind: .refund,
                                 amount: 0, date: .now, state: .refunded, rentalID: rental.id,
                                 title: "Swap · faulty charger",
                                 detail: "Swapped slot \(oldSlot) → \(newSlot). Time on the faulty charger removed."),
                      at: 0)
    }

    func fastForward(hours: Double) {
        guard var r = activeRental else { return }
        r.startedAt = r.startedAt.addingTimeInterval(-hours * 3600)
        activeRental = r
    }

    func replayOnboarding() {
        UserDefaults.standard.set(false, forKey: "cf.onboarded")
        hasSeenOnboarding = false
    }
}
