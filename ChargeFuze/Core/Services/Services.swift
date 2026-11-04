import Foundation
import CoreLocation
import SwiftUI

// MARK: - What the app needs from the backend
// Views never call the network. AppModel talks to these protocols; `Services.mock` runs the demo,
// `Services.live(_:)` talks to the API. To integrate the real backend, fill in the Live* types below
// (paths and payloads are proposals, see INTEGRATION.md) — no view needs to change.

protocol StationService: Sendable {
    /// Kiosks around a point, closest first (the home map shows up to 10).
    func nearby(_ center: CLLocationCoordinate2D, radius: CLLocationDistance) async throws -> [Station]
}

protocol AuthService: Sendable {
    /// Text a 6-digit code (SMS autofill on device).
    func sendCode(to phone: String) async throws
    /// Exchange the code for a session token.
    func verify(phone: String, code: String) async throws -> String
}

protocol RentalService: Sendable {
    /// Pay and ask the kiosk to release a charger (scan-to-rent).
    func start(stationID: String, plan: RentPlan, paymentID: String, promo: String?) async throws -> RentalTicket
    /// Pay ahead while walking; returns the 4-digit code to type on the kiosk.
    func buyUnlockCode(stationID: String, plan: RentPlan, paymentID: String) async throws -> String
    /// Keep the charger longer without a late fee.
    func extend(rentalID: String, hours: Int) async throws
    /// "Charger not working?" → swap reason.
    func reportIssue(rentalID: String, reason: String) async throws
}

protocol ReturnService: Sendable {
    /// Hold one empty slot for 15 min while the user walks to the kiosk.
    func holdSlot(stationID: String) async throws -> HeldSlot
    /// The kiosk didn't confirm the return: file proof (time, slot, distance, optional photo). Returns the ticket id.
    func claimReturn(rentalID: String, stationID: String, slot: Int, evidence: [String], photo: Data?) async throws -> String
    /// Hand the running rental to another account.
    func passRental(rentalID: String, to recipient: String) async throws
}

protocol AccountService: Sendable {
    /// Saved payment methods (Apple Pay, cards, FUZE Cash). Card entry itself goes through the payment SDK.
    func paymentMethods() async throws -> [PaymentMethod]
    /// Past rentals for the Rentals screen.
    func history() async throws -> [RentalRecord]
    /// Money activity: holds, charges, refunds, passes.
    func ledger() async throws -> [ChargeLine]
    /// Redeem a promo code; returns the credit added (USD).
    func redeemPromo(_ code: String) async throws -> Double
    /// Buy a Festival Pass for a venue.
    func buyPass(stationID: String) async throws
}

protocol SupportService: Sendable {
    /// Open a help ticket; returns the server's ticket id.
    func openTicket(issue: IssueKind, rentalID: String?, note: String, evidence: [String]) async throws -> String
}

/// What the kiosk tells the backend; the app follows these (never asks a dying phone to confirm).
enum KioskEvent: String, Codable, Sendable {
    case codeUsed = "code_used", chargerReleased = "charger_released", chargerTaken = "charger_taken"
    case chargerInserted = "charger_inserted", chargerLocked = "charger_locked"
    case releaseFailed = "release_failed", faultySeated = "faulty_seated", newReleased = "new_released"
}

protocol KioskEventService: Sendable {
    /// Live events for one rental (WebSocket / SSE in production).
    func events(rentalID: String) -> AsyncStream<KioskEvent>
}

struct RentalTicket: Codable, Sendable, Hashable {
    let rentalID: String
    let startedAt: Date
    /// Slot the kiosk will release (nil until the kiosk answers).
    var slot: Int? = nil
}

/// Everything the app depends on, swappable as a unit (demo, preview, staging, production).
struct Services: Sendable {
    var stations: any StationService
    var auth: any AuthService
    var rentals: any RentalService
    var kiosk: any KioskEventService
    var returns: any ReturnService
    var account: any AccountService
    var support: any SupportService

    static let mock = Services(stations: MockStationService(), auth: MockAuthService(),
                               rentals: MockRentalService(), kiosk: MockKioskEventService(),
                               returns: MockReturnService(), account: MockAccountService(), support: MockSupportService())

    static func live(_ api: APIClient) -> Services {
        Services(stations: LiveStationService(api: api), auth: LiveAuthService(api: api),
                 rentals: LiveRentalService(api: api), kiosk: LiveKioskEventService(api: api),
                 returns: LiveReturnService(api: api), account: LiveAccountService(api: api), support: LiveSupportService(api: api))
    }

    /// Live when Info.plist has API_BASE_URL, otherwise the demo data.
    static var current: Services { APIClient.configured.map(live) ?? .mock }
}

extension EnvironmentValues {
    @Entry var services: Services = .mock
}

// MARK: - Mock (demo + previews)

struct MockStationService: StationService {
    func nearby(_ center: CLLocationCoordinate2D, radius: CLLocationDistance) async throws -> [Station] {
        let me = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return MockData.stations.filter { me.distance(from: $0.location) < radius }
            .sorted { me.distance(from: $0.location) < me.distance(from: $1.location) }
    }
}

struct MockAuthService: AuthService {
    func sendCode(to phone: String) async throws { try await Task.sleep(for: .milliseconds(300)) }
    /// Demo code is 1234 (the sign-in sheet offers it as the SMS autofill).
    func verify(phone: String, code: String) async throws -> String {
        guard code == "1234" else { throw APIError.http(status: 401, message: "That code isn't right.") }
        return "demo-token"
    }
}

struct MockRentalService: RentalService {
    func start(stationID: String, plan: RentPlan, paymentID: String, promo: String?) async throws -> RentalTicket {
        RentalTicket(rentalID: "R-" + String(UUID().uuidString.prefix(6)), startedAt: .now)
    }
    func buyUnlockCode(stationID: String, plan: RentPlan, paymentID: String) async throws -> String { String(Int.random(in: 4000...9999)) }
    func extend(rentalID: String, hours: Int) async throws {}
    func reportIssue(rentalID: String, reason: String) async throws {}
}

struct MockKioskEventService: KioskEventService {
    func events(rentalID: String) -> AsyncStream<KioskEvent> {
        AsyncStream { c in
            Task { try? await Task.sleep(for: .seconds(1.5)); c.yield(.chargerReleased); try? await Task.sleep(for: .seconds(2)); c.yield(.chargerTaken); c.finish() }
        }
    }
}

struct MockReturnService: ReturnService {
    func holdSlot(stationID: String) async throws -> HeldSlot {
        HeldSlot(stationID: stationID, slot: [3, 5, 8, 11, 14].randomElement()!, until: .now.addingTimeInterval(15 * 60))
    }
    func claimReturn(rentalID: String, stationID: String, slot: Int, evidence: [String], photo: Data?) async throws -> String {
        "T-" + String(Int.random(in: 10_000...99_999))
    }
    func passRental(rentalID: String, to recipient: String) async throws {}
}

struct MockAccountService: AccountService {
    func paymentMethods() async throws -> [PaymentMethod] { [MockData.applePay, MockData.visa, MockData.mastercard, MockData.fuzeCash] }
    func history() async throws -> [RentalRecord] { MockData.history() }
    func ledger() async throws -> [ChargeLine] { AppModel.seedLedger() }
    func redeemPromo(_ code: String) async throws -> Double {
        guard code.trimmingCharacters(in: .whitespaces).count >= 4 else { throw APIError.http(status: 404, message: "That code isn't valid.") }
        return 2
    }
    func buyPass(stationID: String) async throws {}
}

struct MockSupportService: SupportService {
    func openTicket(issue: IssueKind, rentalID: String?, note: String, evidence: [String]) async throws -> String {
        "T-" + String(Int.random(in: 10_000...99_999))
    }
}

// MARK: - Live (fill in the paths with the backend team)

struct StationDTO: Codable, Sendable {
    let id: String, venue: String, spot: String
    let floor: String?
    let indoor: Bool?
    let lat: Double, lng: Double
    let chargers: Int, emptySlots: Int
    let hours: String, online: Bool
    let blockMinutes: Double?, pricePerBlock: Double?, dailyMax: Double?

    var model: Station {
        var r = Rate.city
        if let b = blockMinutes, let p = pricePerBlock, let m = dailyMax { r = Rate(blockMinutes: b, pricePerBlock: p, dailyMax: m) }
        return Station(id: id, venue: venue, spot: spot, latitude: lat, longitude: lng, chargers: chargers,
                       returnSlots: emptySlots, hours: hours, status: online ? .online : .offline, rate: r, floor: floor, indoor: indoor ?? false)
    }
}

struct LiveStationService: StationService {
    let api: APIClient
    func nearby(_ c: CLLocationCoordinate2D, radius: CLLocationDistance) async throws -> [Station] {
        let ep = Endpoint<[StationDTO]>(path: "v1/stations/nearby", query: [
            .init(name: "lat", value: "\(c.latitude)"), .init(name: "lng", value: "\(c.longitude)"), .init(name: "radius", value: "\(Int(radius))")])
        return try await api.send(ep).map(\.model)
    }
}

struct LiveAuthService: AuthService {
    let api: APIClient
    private struct Phone: Encodable { let phone: String }
    private struct Verify: Encodable { let phone: String; let code: String }
    private struct Token: Decodable, Sendable { let token: String }
    func sendCode(to phone: String) async throws { _ = try await api.send(Endpoint<Empty>.post("v1/auth/code", Phone(phone: phone))) }
    func verify(phone: String, code: String) async throws -> String {
        try await api.send(Endpoint<Token>.post("v1/auth/verify", Verify(phone: phone, code: code))).token
    }
}

struct LiveRentalService: RentalService {
    let api: APIClient
    private struct Start: Encodable { let stationId: String; let plan: String; let paymentId: String; let promo: String? }
    private struct Code: Decodable, Sendable { let code: String }
    private struct Extend: Encodable { let hours: Int }
    private struct Issue: Encodable { let reason: String }
    func start(stationID: String, plan: RentPlan, paymentID: String, promo: String?) async throws -> RentalTicket {
        try await api.send(Endpoint<RentalTicket>.post("v1/rentals", Start(stationId: stationID, plan: plan.rawValue, paymentId: paymentID, promo: promo)))
    }
    func buyUnlockCode(stationID: String, plan: RentPlan, paymentID: String) async throws -> String {
        try await api.send(Endpoint<Code>.post("v1/unlock-codes", Start(stationId: stationID, plan: plan.rawValue, paymentId: paymentID, promo: nil))).code
    }
    func extend(rentalID: String, hours: Int) async throws {
        _ = try await api.send(Endpoint<Empty>.post("v1/rentals/\(rentalID)/extend", Extend(hours: hours)))
    }
    func reportIssue(rentalID: String, reason: String) async throws {
        _ = try await api.send(Endpoint<Empty>.post("v1/rentals/\(rentalID)/issues", Issue(reason: reason)))
    }
}

/// Kiosk events over Server-Sent Events: `GET v1/rentals/{id}/events`, lines `data: charger_released`.
struct LiveKioskEventService: KioskEventService {
    let api: APIClient
    func events(rentalID: String) -> AsyncStream<KioskEvent> {
        AsyncStream { c in
            let task = Task {
                do {
                    for try await line in try await api.lines(Endpoint<Empty>(path: "v1/rentals/\(rentalID)/events")) {
                        guard line.hasPrefix("data:") else { continue }
                        let raw = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if let e = KioskEvent(rawValue: raw) { c.yield(e) }
                    }
                } catch {}
                c.finish()
            }
            c.onTermination = { _ in task.cancel() }
        }
    }
}

struct LiveReturnService: ReturnService {
    let api: APIClient
    private struct Hold: Decodable, Sendable { let slot: Int; let until: Date }
    private struct Station: Encodable { let stationId: String }
    private struct Claim: Encodable { let stationId: String; let slot: Int; let evidence: [String]; let photo: Data? }
    private struct Ticket: Decodable, Sendable { let id: String }
    private struct Pass: Encodable { let recipient: String }
    func holdSlot(stationID: String) async throws -> HeldSlot {
        let h = try await api.send(Endpoint<Hold>.post("v1/slot-holds", Station(stationId: stationID)))
        return HeldSlot(stationID: stationID, slot: h.slot, until: h.until)
    }
    func claimReturn(rentalID: String, stationID: String, slot: Int, evidence: [String], photo: Data?) async throws -> String {
        try await api.send(Endpoint<Ticket>.post("v1/rentals/\(rentalID)/return-claims",
                                                 Claim(stationId: stationID, slot: slot, evidence: evidence, photo: photo))).id
    }
    func passRental(rentalID: String, to recipient: String) async throws {
        _ = try await api.send(Endpoint<Empty>.post("v1/rentals/\(rentalID)/pass", Pass(recipient: recipient)))
    }
}

struct LiveAccountService: AccountService {
    let api: APIClient
    private struct Promo: Encodable { let code: String }
    private struct Credit: Decodable, Sendable { let credit: Double }
    private struct PassBody: Encodable { let stationId: String }
    // TODO(backend): PaymentMethod / RentalRecord / ChargeLine are app models; add DTOs like StationDTO once the JSON is fixed.
    func paymentMethods() async throws -> [PaymentMethod] { MockData.paymentMethods }
    func history() async throws -> [RentalRecord] { [] }
    func ledger() async throws -> [ChargeLine] { [] }
    func redeemPromo(_ code: String) async throws -> Double {
        try await api.send(Endpoint<Credit>.post("v1/promos/redeem", Promo(code: code))).credit
    }
    func buyPass(stationID: String) async throws {
        _ = try await api.send(Endpoint<Empty>.post("v1/passes", PassBody(stationId: stationID)))
    }
}

struct LiveSupportService: SupportService {
    let api: APIClient
    private struct Body: Encodable { let issue: String; let rentalId: String?; let note: String; let evidence: [String] }
    private struct Ticket: Decodable, Sendable { let id: String }
    func openTicket(issue: IssueKind, rentalID: String?, note: String, evidence: [String]) async throws -> String {
        try await api.send(Endpoint<Ticket>.post("v1/tickets", Body(issue: issue.rawValue, rentalId: rentalID, note: note, evidence: evidence))).id
    }
}
