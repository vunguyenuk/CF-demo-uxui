import SwiftUI
import UIKit
import CoreLocation
import UserNotifications

enum AppTab: Hashable { case map, scan, rentals, help, account }

/// Steps of the rent flow, shown as a 4-part progress bar.
enum RentStep: Int, CaseIterable { case scan, pay, take, charging
    var title: String {
        switch self { case .scan: "Scan"; case .pay: "Pay"; case .take: "Take it"; case .charging: "Charging" }
    }
}

enum ReturnStep: Equatable { case find, atStation(Station), verifying(Station), receipt(RentalRecord), notConfirmed(Station), claimSent(SupportTicket) }

@MainActor
@Observable
final class AppModel {
    /// Backend access (mock demo data unless Info.plist has API_BASE_URL). Views never call the network.
    let services: Services
    init(services: Services = .current) {
        self.services = services
        // Demo: sign-in lasts for the app session (like the web). Live: a saved session token.
        signedIn = !(services.auth is MockAuthService) && SessionStore.token != nil
    }

    /// Pull the kiosks around the user from the backend (mock: the demo list).
    func refreshNearby() async {
        if let fresh = try? await services.stations.nearby(userLocation.coordinate, radius: 2_600), !fresh.isEmpty {
            stations = fresh
        }
    }

    /// Live only: payment methods, rentals and money activity for the signed-in account.
    func refreshAccount() async {
        guard !isDemo, signedIn else { return }
        if let m = try? await services.account.paymentMethods(), !m.isEmpty {
            paymentMethods = m
            if !m.contains(where: { $0.id == defaultPaymentID }) { defaultPaymentID = m[0].id }
        }
        if let h = try? await services.account.history() { history = h }
        if let l = try? await services.account.ledger() { ledger = l }
    }

    // Persistence for onboarding only (demo app).
    var hasSeenOnboarding: Bool = UserDefaults.standard.bool(forKey: "cf.onboarded")

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "cf.onboarded")
        hasSeenOnboarding = true
    }

    // Data
    // Data — seeded with the demo set; `refreshNearby()` / `refreshAccount()` replace it from the API.
    var stations: [Station] = MockData.stations
    var history: [RentalRecord] = MockData.history()
    var tickets: [SupportTicket] = []
    var ledger: [ChargeLine] = AppModel.seedLedger()
    var pass: RentalPass? = nil
    var paymentMethods: [PaymentMethod] = MockData.paymentMethods
    var defaultPaymentID: String = MockData.applePay.id
    var userName = MockData.userName
    var phone = UserDefaults.standard.string(forKey: "cf.phone") ?? MockData.phone
    var promoCredit: Double = 0

    // Like the web, demo sign-in lasts for the current app session.
    var signedIn: Bool
    var locationAsked: Bool = UserDefaults.standard.bool(forKey: "cf.locAsked")
    /// Step 1 of sign-in: text a code to the number.
    func sendSignInCode(to phone: String) {
        Task { try? await services.auth.sendCode(to: phone) }
    }

    /// Step 2: check the code. On success the session token goes to the Keychain (live only).
    func verifySignIn(phone: String, code: String) async -> Bool {
        do {
            let token = try await services.auth.verify(phone: phone, code: code)
            if !isDemo { SessionStore.save(token) }
            completeSignIn(phone: phone)
            Task { await refreshAccount() }
            return true
        } catch { return false }
    }

    func completeSignIn(phone: String) {
        self.phone = phone
        if !isDemo { UserDefaults.standard.set(phone, forKey: "cf.phone") }
        signedIn = true
    }

    func signOut() {
        SessionStore.clear()
        UserDefaults.standard.removeObject(forKey: "cf.phone")
        signedIn = false
    }

    var isDemo: Bool { services.auth is MockAuthService }
    func completeLocation() { UserDefaults.standard.set(true, forKey: "cf.locAsked"); locationAsked = true }
    /// Walking to a kiosk (2D route screen). The unlock code bought on the way lives here.
    var walkTo: Station?
    var unlockCode: String?
    private(set) var unlockCodeExpires: Date?
    private var unlockStationID: String?
    /// Show the "pull it out" screen only when the kiosk says the charger is still in the slot.
    var demoChargerNotTaken = false

    /// The 5–10 kiosks closest to the user; ready ones first.
    var nearbyStations: [Station] {
        stations.filter { distance(to: $0) < 2_600 }
            .sorted { a, b in
                let ra = a.status == .online && a.chargers > 0, rb = b.status == .online && b.chargers > 0
                return ra != rb ? ra : distance(to: a) < distance(to: b)
            }
            .prefix(10).map { $0 }
    }

    // Return happens on the home map, in one bottom sheet (no separate screens unless the kiosk can't confirm)
    var returnMode = false
    var receiptSheet: RentalRecord?
    var showAccount = false
    /// Extra hours the user asked to keep the charger without a late fee.
    var keepHours: Int = 0
    var lateFeeFrom: Date? { activeRental.map { $0.startedAt.addingTimeInterval(($0.rate.nonReturnHours + Double(keepHours)) * 3600) } }

    /// At a kiosk with the charger in hand: the kiosk sees it go in, billing stops, the receipt slides up.
    /// The kiosk reported the charger locked into `slot`: close the rental and show the receipt.
    func returnLocked(_ station: Station, slot: Int) {
        completeReturn(at: station, slot: slot)
        receiptSheet = lastReceipt
        returnMode = false; keepHours = 0
    }

    func verifyUnconfirmedReturn(at station: Station) {
        guard activeRental != nil else { return }
        insertedCharger(at: station)
        showReturnFlow = true
    }

    func returnHere(_ station: Station) {
        if demoReturnNotConfirmed { returnStep = .atStation(station); showReturnFlow = true; return }
        Task {
            var slot = [2, 6, 9, 13, 17].randomElement() ?? 6
            if isDemo {
                try? await Task.sleep(for: .seconds(2.4))
            } else if let id = activeRental?.id {
                // Live: wait for the kiosk to lock the charger; no event → ask for proof instead.
                guard await waitForKiosk(rentalID: id, until: [.chargerLocked], timeout: 60) == .chargerLocked else {
                    returnStep = .atStation(station); showReturnFlow = true; return
                }
                slot = heldSlot?.slot ?? slot   // TODO(backend): send the locked slot number with the event
            }
            completeReturn(at: station, slot: slot)
            receiptSheet = lastReceipt
            returnMode = false; keepHours = 0
        }
    }

    // Demo / QA launch arguments live in `Core/Mock/AppModel+Demo.swift`.
    var demoArriveNow = false

    /// Close the walking screen first, then continue (two full-screen covers can't swap in one frame).
    func leaveWalk(then next: @escaping @MainActor () -> Void) {
        walkTo = nil
        directionsTo = nil
        Task { try? await Task.sleep(for: .milliseconds(600)); next() }
    }

    /// Pay while walking: issue a 4-digit code to type on the kiosk screen.
    func buyUnlockCode(at station: Station) {
        rentStation = station
        Task {
            guard let code = try? await services.rentals.buyUnlockCode(stationID: station.id, plan: plan, paymentID: defaultPaymentID) else { return }
            withAnimation(.snappy) {
                unlockCode = code
                unlockCodeExpires = .now.addingTimeInterval(900)
                unlockStationID = station.id
            }
        }
    }

    func unlockCode(for station: Station, at date: Date = .now) -> String? {
        guard unlockStationID == station.id, let unlockCodeExpires, date < unlockCodeExpires else { return nil }
        return unlockCode
    }

    // Navigation
    var tab: AppTab = .map
    var selectedStationID: String?
    var showRentFlow = false
    var showReturnFlow = false
    var showRentalSheet = false
    var directionsTo: Station?
    var showHelp = false
    var showPaySheet = false
    var quickRentStation: Station?
    var showSwap = false
    // Swap entry points: user reports a problem, or the app notices the phone isn't charging
    var showSwapReasons = false
    var swapAuto = false            // opened by the "not charging" detector
    var swapChargingIssue = false
    private var pendingChargingHelp = false
    var swapOnArrival = false       // walking to a kiosk to swap
    var swapWalkOrigin: CLLocation?

    /// After a charger comes out, watch the phone's battery state; if it never starts charging, offer a swap.
    /// "Not charging?" banner on the rental map (set by `watchCharging`).
    var notChargingBanner = false

    func watchCharging() async {
        guard let rentalID = activeRental?.id else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        do { try await Task.sleep(for: .seconds(120)) } catch { return }
        guard activeRental?.id == rentalID, !showSwap, !returnMode, !showReturnFlow,
              UIDevice.current.batteryState == .unplugged else { return }
        swapAuto = true
        // like the web: an iOS-style banner first; tapping it opens "What's wrong?"
        if showRentFlow { pendingChargingHelp = true } else { notChargingBanner = true }
    }
    var plan: RentPlan = .payAsYouGo
    var showRentalsInAccount = false
    var rentStep: RentStep = .scan
    var rentStation: Station?
    var rentSlot: Int = 12
    var ejectFailed = false
    private(set) var waitingForRelease = false
    var returnStep: ReturnStep = .find
    var lastReceipt: RentalRecord?
    var heldSlot: HeldSlot?
    var returnStoppedAt: Date = .now
    var lastReturnByProof = false
    var lastReturnNote: String?

    // Active rental
    var activeRental: Rental?

    // Settings
    var remindersOn = true
    var nearbyAlertsOn = true

    // Demo switches (Account › Demo)
    var demoKioskWontRelease = false
    var demoReturnNotConfirmed = false
    var demoLowBattery = true
    var userLocation: CLLocation = MockData.userLocation

    // MARK: Derived

    var selectedStation: Station? {
        get { stations.first { $0.id == selectedStationID } }
        set { selectedStationID = newValue?.id }
    }
    var defaultPayment: PaymentMethod { paymentMethods.first { $0.id == defaultPaymentID } ?? MockData.applePay }
    var chargersNearby: Int { stations.filter { $0.status == .online }.reduce(0) { $0 + $1.chargers } }

    func distance(to s: Station) -> CLLocationDistance { userLocation.distance(from: s.location) }
    func distanceText(_ s: Station) -> String {
        let miles = distance(to: s) / 1609.34
        return miles < 0.1 ? "Nearby" : String(format: "%.1f mi", miles)
    }
    func walkMinutes(_ s: Station) -> Int { max(1, Int((distance(to: s) / 80).rounded())) }   // ~80 m per minute

    var nearestWithChargers: Station? {
        stations.filter { $0.status == .online && $0.chargers > 0 }.min { distance(to: $0) < distance(to: $1) }
    }
    var returnCandidates: [Station] {
        stations.filter { $0.status == .online && $0.returnSlots > 0 }.sorted { distance(to: $0) < distance(to: $1) }
    }

    func station(withCode code: String) -> Station? {
        let c = code.uppercased().replacingOccurrences(of: " ", with: "")
        return stations.first { $0.id.replacingOccurrences(of: "-", with: "") == c.replacingOccurrences(of: "-", with: "") }
    }

    // MARK: Rent flow

    func startRentFlow(at station: Station? = nil) {
        rentStation = station
        rentStep = station == nil ? .scan : .scan
        ejectFailed = false
        showRentFlow = true
    }

    /// Scanned → the scanner closes and a small "Rent a charger" sheet opens over the map.
    func didScan(_ station: Station) {
        rentStation = station
        showRentFlow = false
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            if isDemo, unlockCode(for: station) != nil { redeemDemoUnlockCode(at: station) }
            else { showPaySheet = true }
        }
    }

    /// Payment approved → kiosk is told to release a charger.
    func pay() {
        guard let station = rentStation, activeRental == nil,
              !showRentFlow || rentStep == .pay || ejectFailed else { return }
        let availableSlots = [3, 7, 12, 18, 22].filter { !ejectFailed || $0 != rentSlot }
        rentSlot = availableSlots.randomElement() ?? 12
        ejectFailed = false
        // Happy path goes straight to "Plug the cable in". The take screen only appears when
        // the kiosk reports a problem (didn't release, or the charger is still in the slot).
        let releaseFails = demoKioskWontRelease
        waitingForRelease = releaseFails
        let interrupted = releaseFails || demoChargerNotTaken
        demoKioskWontRelease = false
        demoChargerNotTaken = false
        rentStep = interrupted ? .take : .charging
        showPaySheet = false
        showRentFlow = true
        unlockCode = nil
        unlockCodeExpires = nil
        unlockStationID = nil
        let plan = plan, paymentID = defaultPaymentID
        Task {
            // Pay + ask the kiosk to release (mock answers at once).
            guard let ticket = try? await services.rentals.start(stationID: station.id, plan: plan, paymentID: paymentID, promo: nil) else {
                waitingForRelease = false
                withAnimation(.smooth) { ejectFailed = true }   // payment or kiosk refused: nothing charged
                return
            }
            if let slot = ticket.slot { rentSlot = slot }
            var failed = releaseFails
            if isDemo {
                if interrupted {
                    do { try await Task.sleep(for: .seconds(4.2)) } catch { return }
                    guard showRentFlow, rentStep == .take else { return }
                }
            } else {
                // Live: the kiosk reports release / failure; the app never asks the user to confirm.
                let e = await waitForKiosk(rentalID: ticket.rentalID, until: [.chargerReleased, .chargerTaken, .releaseFailed], timeout: 30)
                failed = e != .chargerReleased && e != .chargerTaken
            }
            waitingForRelease = false
            if failed {
                withAnimation(.smooth) { ejectFailed = true }   // auto-cancel, nothing charged
                return
            }
            let rental = Rental(id: ticket.rentalID, station: station, slot: rentSlot,
                                startedAt: ticket.startedAt, payment: defaultPayment)
            activeRental = rental
            ledger.insert(ChargeLine(id: "L-" + UUID().uuidString.prefix(6), kind: .hold, amount: station.rate.hold, date: .now,
                                     state: .pending, rentalID: rental.id, title: "Temporary hold",
                                     detail: "Not a charge. Released automatically when you return the charger. Your bank may take up to 5 business days to show it."),
                          at: 0)
            if let i = stations.firstIndex(where: { $0.id == station.id }) {
                stations[i].chargers -= 1
                stations[i].returnSlots += 1
            }
            withAnimation(.smooth) { rentStep = .charging }
            scheduleReminders()
        }
    }

    func finishRentFlow(reportNotCharging: Bool = false) {
        if reportNotCharging {
            swapAuto = false
            swapChargingIssue = true
            pendingChargingHelp = true
        }
        showRentFlow = false
        rentStep = .scan
        ejectFailed = false
        waitingForRelease = false
    }

    func rentFlowDidDismiss() {
        guard pendingChargingHelp else { return }
        pendingChargingHelp = false
        guard activeRental != nil else { return }
        showSwapReasons = true
    }

    /// First kiosk event in `until`, or nil after `timeout` seconds.
    func waitForKiosk(rentalID: String, until wanted: Set<KioskEvent>, timeout: Double) async -> KioskEvent? {
        let stream = services.kiosk.events(rentalID: rentalID)
        return await withTaskGroup(of: KioskEvent?.self) { group in
            group.addTask { for await e in stream where wanted.contains(e) { return e }; return nil }
            group.addTask { try? await Task.sleep(for: .seconds(timeout)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// "Keep it longer": no late fee for `hours` more.
    func keepLonger(hours: Int) {
        keepHours = hours
        guard let id = activeRental?.id else { return }
        Task { try? await services.rentals.extend(rentalID: id, hours: hours) }
    }

    /// "Charger not working?" → tell the backend why before the swap.
    func reportChargerIssue(_ reason: String) {
        guard let id = activeRental?.id else { return }
        Task { try? await services.rentals.reportIssue(rentalID: id, reason: reason) }
    }

    // MARK: Return flow

    func startReturnFlow() {
        returnStep = .find
        showRentalSheet = false
        withAnimation(.smooth) { returnMode = true }
    }

    /// At the station the kiosk sees the charger go in, so we skip the "put it back" screen and verify
    /// straight away. The insert screen only shows when the kiosk hasn't confirmed (demo switch).
    func arrived(at station: Station) {
        if demoReturnNotConfirmed { withAnimation(.smooth) { returnStep = .atStation(station) } }
        else { insertedCharger(at: station) }
    }

    /// Slot reservation: one empty slot is held for 15 minutes while the person walks over.
    func holdSlot(at station: Station) {
        Task {
            guard let hold = try? await services.returns.holdSlot(stationID: station.id) else { return }
            withAnimation(.bouncy) { heldSlot = hold }
        }
    }

    /// 1-tap proof of return: billing freezes the moment they tap, before the kiosk answers.
    func insertedCharger(at station: Station) {
        returnStoppedAt = .now
        withAnimation(.smooth) { returnStep = .verifying(station) }
    }

    /// Hand the charger to someone else: the rental moves to their account and this one closes now.
    func passRental(to name: String) {
        guard let r = activeRental else { return }
        lastReturnNote = "Passed to \(name)"
        Task { try? await services.returns.passRental(rentalID: r.id, to: name) }
        completeReturn(at: r.station, slot: 0)
    }

    func completeReturn(at station: Station, slot: Int, endedAt: Date = .now) {
        guard let r = activeRental else { return }
        let record = RentalRecord(id: r.id, pickup: r.station, dropoff: station, returnSlot: slot,
                                  startedAt: r.startedAt, endedAt: endedAt, total: r.cost(at: endedAt),
                                  payment: r.payment, holdReleased: false)
        history.insert(record, at: 0)
        lastReceipt = record
        postRentalCharge(record)
        activeRental = nil
        if let i = stations.firstIndex(where: { $0.id == station.id }) {
            stations[i].returnSlots = max(0, stations[i].returnSlots - 1)
            stations[i].chargers += 1
        }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        withAnimation(.smooth) { returnStep = .receipt(record) }
        Task {   // the hold is released a moment later, the receipt updates live
            try? await Task.sleep(for: .seconds(3))
            if let i = history.firstIndex(where: { $0.id == record.id }) { history[i].holdReleased = true }
            if case .receipt(var rec) = returnStep, rec.id == record.id { rec.holdReleased = true; returnStep = .receipt(rec) }
        }
    }

    /// "Returned but not confirmed": billing evidence is saved with the time of return.
    func submitReturnClaim(station: Station, slot: Int, hasPhoto: Bool) {
        let returnedAt = Date.now
        var evidence = ["Returned at \(returnedAt.shortTime) · \(station.venue)", "Slot \(slot)",
                        "Phone was \(Int(distance(to: station)))\u{00A0}m from the kiosk"]
        if hasPhoto { evidence.append("Photo of the charger in the slot") }
        let ticket = SupportTicket(id: "T-" + String(Int.random(in: 10_000...99_999)), issue: .returnedStillCharged,
                                   rentalID: activeRental?.id, createdAt: returnedAt, status: .received,
                                   note: "We stopped the clock at \(returnedAt.shortTime). You'll get an answer by tonight.",
                                   evidence: evidence)
        tickets.insert(ticket, at: 0)
        if let rid = activeRental?.id {   // TODO(backend): show the server's ticket id once it answers
            let sid = station.id
            Task { _ = try? await services.returns.claimReturn(rentalID: rid, stationID: sid, slot: slot, evidence: evidence, photo: nil) }
        }
        // The rental is closed at the claimed time; the kiosk log confirms it later.
        completeReturnSilently(at: station, slot: slot, endedAt: returnedAt)
        withAnimation(.smooth) { returnStep = .claimSent(ticket) }
    }

    private func completeReturnSilently(at station: Station, slot: Int, endedAt: Date) {
        guard let r = activeRental else { return }
        let record = RentalRecord(id: r.id, pickup: r.station, dropoff: station, returnSlot: slot, startedAt: r.startedAt,
                                  endedAt: endedAt, total: r.cost(at: endedAt), payment: r.payment, holdReleased: false)
        history.insert(record, at: 0)
        postRentalCharge(record)
        activeRental = nil
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func finishReturnFlow() {
        showReturnFlow = false
        returnStep = .find
        heldSlot = nil
        lastReturnByProof = false
        lastReturnNote = nil
    }

    // MARK: Money activity

    private func postRentalCharge(_ record: RentalRecord) {
        ledger.insert(ChargeLine(id: "L-" + UUID().uuidString.prefix(6), kind: .rental, amount: record.total, date: record.endedAt,
                                 state: .posted, rentalID: record.id, title: "Rental · \(record.pickup.venue)",
                                 detail: "\(record.blocks) × \(record.rate.headline) · \(record.duration.friendly). Returned to slot \(record.returnSlot) at \(record.dropoff.venue), \(record.endedAt.shortTime)."),
                      at: 0)
        if let i = ledger.firstIndex(where: { $0.rentalID == record.id && $0.kind == .hold }) {
            ledger[i].state = .released
        }
    }

    func lines(for rentalID: String) -> [ChargeLine] { ledger.filter { $0.rentalID == rentalID } }

    nonisolated static func seedLedger(now: Date = .now) -> [ChargeLine] {
        MockData.history(now: now).flatMap { r in [
            ChargeLine(id: "L-\(r.id)-c", kind: .rental, amount: r.total, date: r.endedAt, state: .posted, rentalID: r.id,
                       title: "Rental · \(r.pickup.venue)",
                       detail: "\(r.blocks) × \(r.rate.headline) · \(r.duration.friendly). Returned to slot \(r.returnSlot) at \(r.dropoff.venue)."),
            ChargeLine(id: "L-\(r.id)-h", kind: .hold, amount: r.rate.hold, date: r.startedAt, state: .released, rentalID: r.id,
                       title: "Temporary hold", detail: "Released when the charger was returned. It was never a charge."),
        ] }
    }

    func buyFestivalPass(at station: Station) {
        let sid = station.id
        Task { try? await services.account.buyPass(stationID: sid) }
        let start = Date.now
        pass = RentalPass(name: "Festival Pass", venue: station.venue, price: 60, startedAt: start,
                          endsAt: start.addingTimeInterval(48 * 3600),
                          note: "Unlimited swaps for 48 hours. Return the last charger before the pass ends.")
        ledger.insert(ChargeLine(id: "L-" + UUID().uuidString.prefix(6), kind: .pass, amount: 60, date: start, state: .posted,
                                 rentalID: nil, title: "Festival Pass · \(station.venue)",
                                 detail: "Valid until \(start.addingTimeInterval(48 * 3600).shortDay), \(start.addingTimeInterval(48 * 3600).shortTime). Plus local tax."),
                      at: 0)
    }

    // MARK: Help

    @discardableResult
    func openTicket(_ issue: IssueKind, rentalID: String?, note: String) -> SupportTicket {
        let t = SupportTicket(id: "T-" + String(Int.random(in: 10_000...99_999)), issue: issue, rentalID: rentalID,
                              createdAt: .now, status: .received, note: note.isEmpty ? issue.reassurance : note, evidence: [])
        tickets.insert(t, at: 0)
        Task { _ = try? await services.support.openTicket(issue: issue, rentalID: rentalID, note: t.note, evidence: []) }
        return t
    }

    // MARK: Reminders (S4)

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func scheduleReminders() {
        guard remindersOn, let r = activeRental else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        func add(_ id: String, after seconds: TimeInterval, title: String, body: String) {
            let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
            let t = UNTimeIntervalNotificationTrigger(timeInterval: max(5, seconds), repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: c, trigger: t))
        }
        let rate = r.rate
        // 5 minutes before each of the first 4 blocks ends: "return now and save $X"
        for i in 1...4 {
            let end = Double(i) * rate.blockMinutes * 60
            add("cf.block\(i)", after: end - 300, title: "Next \(rate.pricePerBlock.usd) starts in 5 min",
                body: "Return now to pay \(rate.cost(for: end - 1).usd) instead of \(rate.cost(for: end + 1).usd). Closest free slot: \(returnCandidates.first?.venue ?? "nearby").")
        }
        add("cf.max", after: r.dailyMaxAt.timeIntervalSinceNow - 600, title: "You've almost reached the \(rate.dailyMax.usd) daily max",
            body: "It won't go higher today. Return within \(Int(rate.nonReturnHours)) hours to avoid the \(rate.nonReturnFee.usd) fee.")
        add("cf.48h", after: r.nonReturnAt.timeIntervalSinceNow - 2 * 3600, title: "2 hours left to return your charger",
            body: "After \(Int(rate.nonReturnHours)) hours a \(rate.nonReturnFee.usd) fee applies. Tap to find the closest free slot.")
    }

    // MARK: Promo

    func applyPromo(_ code: String) async -> Bool {
        guard let credit = try? await services.account.redeemPromo(code) else { return false }
        promoCredit += credit
        return true
    }
}
