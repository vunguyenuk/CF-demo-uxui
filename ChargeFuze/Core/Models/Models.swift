import Foundation
import CoreLocation

// MARK: - Station

struct Station: Identifiable, Hashable {
    enum Status: Hashable { case online, offline }

    let id: String            // e.g. "CF-1293" — also the code printed under the kiosk QR
    let venue: String         // "Weathered Souls Brewing Co."
    let spot: String          // "Bar Counter Top"
    let latitude: Double
    let longitude: Double
    var chargers: Int         // ready to rent
    var returnSlots: Int      // empty slots that accept a return
    let hours: String
    var status: Status = .online
    var rate: Rate = .city
    var floor: String? = nil  // Venue label, e.g. "Level 2" or "B1".
    var indoor = false

    var isInsideVenue: Bool { indoor || floorLabel != nil }

    var floorLabel: String? {
        guard let label = floor?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else { return nil }
        return label
    }

    var kioskLocation: String {
        guard let floorLabel else { return spot }
        return spot.isEmpty ? floorLabel : "\(floorLabel) · \(spot)"
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var location: CLLocation { .init(latitude: latitude, longitude: longitude) }

    /// Which kiosk model sits at this venue (drives the 3D map icon). Real data comes from the backend.
    var kioskType: String { ["standard", "tower", "mini", "wide"][id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 4] }
    /// Blender render of this venue's kiosk model, shown as-is (no tile behind it) on the map, list and cards.
    var kioskImage: String { kioskType == "standard" ? "Kiosk3D" : "Kiosk3D_\(kioskType)" }

    enum PinKind { case ready, empty, offline }
    var pinKind: PinKind {
        if status == .offline { return .offline }
        return chargers > 0 ? .ready : .empty
    }
}

// MARK: - Pricing
// Prices differ by venue (city kiosks: $1 / 30 min; festivals: $10 / hour, each started hour billed in full).
// The app never assumes one price: it always shows the rate of the station in front of you.

struct Rate: Hashable {
    var blockMinutes: Double
    var pricePerBlock: Double
    var dailyMax: Double
    var hold: Double = 10
    var nonReturnHours: Double = 48
    var nonReturnFee: Double = 40
    var taxNote: String? = nil

    /// City kiosks, as shown in the current app: $1 / 30 min, $15 daily max, $40 after 48 h.
    static let city = Rate(blockMinutes: 30, pricePerBlock: 1, dailyMax: 15)
    /// Festival kiosks (Reddit r/festivals): $10 per started hour, plus tax.
    static let festival = Rate(blockMinutes: 60, pricePerBlock: 10, dailyMax: 40, nonReturnFee: 54, taxNote: "plus local tax")

    var blockLabel: String { blockMinutes == 60 ? "hour" : "\(Int(blockMinutes)) min" }
    /// "$1 per 30 min" · "$10 per hour"
    var headline: String { "\(pricePerBlock.usd) per \(blockLabel)" }

    /// Cost for a rental that has run `seconds`.
    func cost(for seconds: TimeInterval) -> Double {
        if seconds / 3600 >= nonReturnHours { return nonReturnFee }
        let days = floor(seconds / 86_400)
        let rest = seconds - days * 86_400
        let blocks = max(1, ceil(rest / (blockMinutes * 60)))
        return days * dailyMax + min(blocks * pricePerBlock, dailyMax)
    }

    /// Seconds until the next block is added (nil once today's max is reached).
    func secondsToNextCharge(after seconds: TimeInterval) -> TimeInterval? {
        let rest = seconds.truncatingRemainder(dividingBy: 86_400)
        let blocksSoFar = max(1, ceil(max(rest, 1) / (blockMinutes * 60)))
        if blocksSoFar * pricePerBlock >= dailyMax { return nil }
        return blocksSoFar * blockMinutes * 60 - rest
    }

    var dailyMaxAfter: TimeInterval { (dailyMax / pricePerBlock).rounded(.up) * blockMinutes * 60 }

    /// Plain-language examples shown before renting.
    var examples: [(label: String, price: Double)] {
        let one = blockMinutes * 60
        return [(blockMinutes == 60 ? "1 hour" : "30 min", cost(for: one)),
                ("2 h 10 min", cost(for: 130 * 60)),
                ("All day", dailyMax)]
    }
}

// MARK: - Rental

struct Rental: Identifiable, Hashable {
    let id: String
    let station: Station
    let slot: Int
    var startedAt: Date
    var payment: PaymentMethod

    var rate: Rate { station.rate }
    func elapsed(at now: Date = .now) -> TimeInterval { max(0, now.timeIntervalSince(startedAt)) }
    func cost(at now: Date = .now) -> Double { rate.cost(for: elapsed(at: now)) }
    func nextChargeIn(at now: Date = .now) -> TimeInterval? { rate.secondsToNextCharge(after: elapsed(at: now)) }
    var dailyMaxAt: Date { startedAt.addingTimeInterval(rate.dailyMaxAfter) }
    var nonReturnAt: Date { startedAt.addingTimeInterval(rate.nonReturnHours * 3600) }
}

struct RentalRecord: Identifiable, Hashable {
    let id: String
    let pickup: Station
    let dropoff: Station
    let returnSlot: Int
    let startedAt: Date
    let endedAt: Date
    let total: Double
    let payment: PaymentMethod
    var holdReleased: Bool

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    var rate: Rate { pickup.rate }
    var blocks: Int { max(1, Int(ceil(duration / (rate.blockMinutes * 60)))) }
}

// MARK: - Payment

struct PaymentMethod: Identifiable, Hashable {
    enum Kind: Hashable { case applePay, card(brand: String, last4: String, expires: String, expired: Bool), fuzeCash(balance: Double) }
    let id: String
    let kind: Kind

    var title: String {
        switch kind {
        case .applePay: "Apple Pay"
        case .card(let brand, let last4, _, _): "\(brand) •••• \(last4)"
        case .fuzeCash: "FUZE Cash"
        }
    }
    var subtitle: String? {
        switch kind {
        case .applePay: nil
        case .card(_, _, let exp, let expired): expired ? "Expired \(exp) · update to use it" : "Expires \(exp)"
        case .fuzeCash(let balance): "\(balance.usd) available"
        }
    }
    var systemImage: String {
        switch kind {
        case .applePay: "apple.logo"
        case .card: "creditcard.fill"
        case .fuzeCash: "bolt.circle.fill"
        }
    }
    var isUsable: Bool {
        switch kind {
        case .card(_, _, _, let expired): !expired
        case .fuzeCash(let balance): balance >= 10
        default: true
        }
    }
}

// MARK: - Money activity (every hold, charge and release, in words — Reddit r/bonnaroo)

struct ChargeLine: Identifiable, Hashable {
    enum Kind: Hashable { case hold, rental, pass, lateFee, refund }
    enum State: String { case pending = "Pending", posted = "Charged", released = "Released", refunded = "Refunded" }
    let id: String
    let kind: Kind
    let amount: Double
    let date: Date
    var state: State
    let rentalID: String?
    let title: String
    let detail: String

    var isMoneyLeaving: Bool { state == .posted }
    var systemImage: String {
        switch kind {
        case .hold: "lock.fill"
        case .rental: "bolt.fill"
        case .pass: "ticket.fill"
        case .lateFee: "exclamationmark.triangle.fill"
        case .refund: "arrow.uturn.backward.circle.fill"
        }
    }
}

struct RentalPass: Hashable {
    let name: String
    let venue: String
    let price: Double
    let startedAt: Date
    let endsAt: Date
    let note: String
}

// MARK: - Support

enum IssueKind: String, CaseIterable, Identifiable {
    case returnedStillCharged, noEject, notCharging, unexpectedCharge, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .returnedStillCharged: "I returned it but I'm still being charged"
        case .noEject: "The kiosk didn't release a charger"
        case .notCharging: "My charger isn't charging"
        case .unexpectedCharge: "I was charged more than I expected"
        case .other: "Something else"
        }
    }
    var systemImage: String {
        switch self {
        case .returnedStillCharged: "arrow.uturn.down.circle.fill"
        case .noEject: "tray.and.arrow.up.fill"
        case .notCharging: "battery.0percent"
        case .unexpectedCharge: "dollarsign.circle.fill"
        case .other: "ellipsis.bubble.fill"
        }
    }
    /// What the user sees the moment they tap the issue (answer first, form second).
    var reassurance: String {
        switch self {
        case .returnedStillCharged: "Billing stops at the time you returned it. Add the slot photo and we'll match it with the kiosk log."
        case .noEject: "If no charger came out within 20 seconds, the rental is cancelled automatically and you're not charged."
        case .notCharging: "Swap it for another charger at any station. The faulty one is flagged and the time on it is removed."
        case .unexpectedCharge: "The $10 hold isn't a charge, it's released after your return. Each started block is billed in full; your breakdown shows every block."
        case .other: "Tell us what happened. A person replies, usually within the hour, 8 AM – 10 PM."
        }
    }
}

struct SupportTicket: Identifiable, Hashable {
    enum Status: String { case received = "Received", reviewing = "In review", resolved = "Resolved" }
    let id: String
    let issue: IssueKind
    let rentalID: String?
    let createdAt: Date
    var status: Status
    var note: String
    var evidence: [String]   // "Photo of slot 12", "Location 0.02 mi from kiosk", …
}

enum RentPlan: String, CaseIterable, Identifiable, Sendable { case payAsYouGo, hourly, dayPass; var id: String { rawValue } }

/// One empty slot held for the user for 15 minutes while they walk to return.
struct HeldSlot: Equatable, Sendable { let stationID: String; let slot: Int; let until: Date }
