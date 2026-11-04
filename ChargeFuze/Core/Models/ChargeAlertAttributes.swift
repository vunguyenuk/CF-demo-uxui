import ActivityKit
import UIKit

/// Same shape as the widget extension's copy (ChargeFuzeWidgets/LowBatteryLiveActivity.swift).
struct ChargeAlertAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var battery: Int
        var minutes: Int
        var chargers: Int
    }
    var venue: String
    var stationID: String
}


struct RentalAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var costSoFar: Double
        var nextChargeAt: Date?
    }
    var venue: String
    var rentalID: String
    var startedAt: Date
    var priceLabel: String
    var dailyMax: Double
}

extension AppModel {
    /// Real level when the device reports one; 18% for the demo switch.
    var batteryPercent: Int {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let l = UIDevice.current.batteryLevel
        return l < 0 ? 30 : Int((l * 100).rounded())
    }

    /// Low battery is shown outside the app: Lock Screen + Dynamic Island Live Activity.
    func updateLowBatteryActivity() {
        let low = demoLowBattery || batteryPercent <= 30
        guard low, activeRental == nil, let s = nearestWithChargers,
              ActivityAuthorizationInfo().areActivitiesEnabled else { endLowBatteryActivity(); return }
        let state = ChargeAlertAttributes.ContentState(battery: demoLowBattery ? 30 : batteryPercent,
                                                       minutes: walkMinutes(s), chargers: s.chargers)
        if !Activity<ChargeAlertAttributes>.activities.isEmpty {
            // look the activity up inside the task (Swift 6: don't send a non-Sendable Activity across tasks)
            Task { await Activity<ChargeAlertAttributes>.activities.first?.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            _ = try? Activity.request(attributes: ChargeAlertAttributes(venue: s.venue, stationID: s.id),
                                      content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(3600)),
                                      pushType: nil)
        }
    }

    func endLowBatteryActivity() {
        Task { for a in Activity<ChargeAlertAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) } }
    }

    /// The running rental as a Live Activity (Lock Screen + Dynamic Island).
    func startRentalActivity() {
        guard let r = activeRental, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endRentalActivity()
        let attrs = RentalAttributes(venue: r.station.venue, rentalID: r.id, startedAt: r.startedAt,
                                     priceLabel: "\(r.rate.pricePerBlock.usd) per \(r.rate.blockLabel)", dailyMax: r.rate.dailyMax)
        let state = RentalAttributes.ContentState(costSoFar: r.cost(), nextChargeAt: r.nextChargeIn().map { Date.now.addingTimeInterval($0) })
        _ = try? Activity.request(attributes: attrs, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
    }

    func refreshRentalActivity() {
        guard let r = activeRental, !Activity<RentalAttributes>.activities.isEmpty else { return }
        let state = RentalAttributes.ContentState(costSoFar: r.cost(), nextChargeAt: r.nextChargeIn().map { Date.now.addingTimeInterval($0) })
        Task { await Activity<RentalAttributes>.activities.first?.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func endRentalActivity() {
        Task { for a in Activity<RentalAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) } }
    }

    /// chargefuze://directions/CF-1293 from the Live Activity "Go" button.
    func handle(url: URL) {
        if url.host == "return", activeRental != nil { startReturnFlow(); return }
        if url.host == "quickrent", let s = stations.first(where: { $0.id == url.lastPathComponent }) ?? nearestWithChargers {
            endLowBatteryActivity(); rentStation = s; quickRentStation = s; return
        }
        guard url.scheme == "chargefuze", url.host == "directions",
              let s = stations.first(where: { $0.id == url.lastPathComponent }) else { return }
        endLowBatteryActivity()
        tab = .map
        directionsTo = s
    }
}
