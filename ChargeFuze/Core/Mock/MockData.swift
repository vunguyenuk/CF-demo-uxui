import Foundation
import CoreLocation

/// Demo data around Pershing Square, Downtown LA (the venue names come from the current app's screens).
enum MockData {
    /// Where the demo pretends the user stands (Pershing Square).
    static let userLocation = CLLocation(latitude: 34.0485, longitude: -118.2529)

    static let stations: [Station] = [
        Station(id: "CF-1293", venue: "Weathered Souls Brewing Co.", spot: "Bar Counter Top", latitude: 34.0479, longitude: -118.2512, chargers: 8, returnSlots: 4, hours: "Open 11 AM – 2 AM", indoor: true),
        Station(id: "CF-0142", venue: "Blue Bottle Coffee", spot: "Next to the pickup counter", latitude: 34.0507, longitude: -118.2545, chargers: 6, returnSlots: 4, hours: "Open 7 AM – 7 PM", indoor: true),
        Station(id: "CF-0877", venue: "Grand Central Market", spot: "Hill St entrance", latitude: 34.0509, longitude: -118.2489, chargers: 0, returnSlots: 9, hours: "Open 8 AM – 10 PM"),
        Station(id: "CF-0311", venue: "The Bloc", spot: "By Macy's", latitude: 34.0484, longitude: -118.2573, chargers: 7, returnSlots: 2, hours: "Open 10 AM – 9 PM", floor: "Level 1"),
        Station(id: "CF-0560", venue: "Walt Disney Concert Hall", spot: "Main lobby", latitude: 34.0553, longitude: -118.2498, chargers: 3, returnSlots: 1, hours: "Open during events", indoor: true),
        Station(id: "CF-0233", venue: "Arts District Brewing", spot: "Back patio", latitude: 34.0435, longitude: -118.2468, chargers: 2, returnSlots: 6, hours: "Open 4 PM – 12 AM"),
        Station(id: "CF-0918", venue: "Union Station", spot: "Ticket concourse", latitude: 34.0560, longitude: -118.2365, chargers: 5, returnSlots: 3, hours: "Open 24 hours", indoor: true),
        Station(id: "CF-0402", venue: "Ace Hotel", spot: "Lobby bar", latitude: 34.0416, longitude: -118.2567, chargers: 0, returnSlots: 0, hours: "Open 24 hours", status: .offline, indoor: true),
        Station(id: "CF-0715", venue: "Crypto.com Arena", spot: "Section 111 concourse", latitude: 34.0430, longitude: -118.2673, chargers: 12, returnSlots: 10, hours: "Open during events", rate: .festival, indoor: true),
        Station(id: "CF-0688", venue: "Whole Foods Market", spot: "Front entrance", latitude: 34.0458, longitude: -118.2601, chargers: 4, returnSlots: 5, hours: "Open 7 AM – 10 PM"),
    ]

    static let applePay = PaymentMethod(id: "pm_applepay", kind: .applePay)
    static let visa = PaymentMethod(id: "pm_visa", kind: .card(brand: "Visa", last4: "4242", expires: "08/28", expired: false))
    static let mastercard = PaymentMethod(id: "pm_mc", kind: .card(brand: "Mastercard", last4: "5100", expires: "03/26", expired: true))
    static let fuzeCash = PaymentMethod(id: "pm_cash", kind: .fuzeCash(balance: 0))
    static let paymentMethods = [applePay, visa, mastercard, fuzeCash]

    /// Demo profile (live: comes from the session).
    static let userName = "Vu Nguyen"
    static let phone = "+1 (415) 555-0132"

    static func history(now: Date = .now) -> [RentalRecord] {
        let s = stations
        func rec(_ id: String, _ a: Int, _ b: Int, slot: Int, daysAgo: Double, minutes: Double) -> RentalRecord {
            let start = now.addingTimeInterval(-daysAgo * 86_400)
            let end = start.addingTimeInterval(minutes * 60)
            return RentalRecord(id: id, pickup: s[a], dropoff: s[b], returnSlot: slot, startedAt: start, endedAt: end,
                                total: s[a].rate.cost(for: minutes * 60), payment: applePay, holdReleased: true)
        }
        return [
            rec("R-8F21C4", 1, 9, slot: 7, daysAgo: 2, minutes: 42),
            rec("R-7D1A09", 6, 6, slot: 3, daysAgo: 4, minutes: 25),
            rec("R-6B44E2", 3, 2, slot: 11, daysAgo: 5, minutes: 70),
            rec("R-5C0F7A", 8, 0, slot: 2, daysAgo: 13, minutes: 55),
        ]
    }
}
