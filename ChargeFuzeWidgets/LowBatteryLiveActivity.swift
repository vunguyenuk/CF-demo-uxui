import ActivityKit
import WidgetKit
import SwiftUI

/// Must match ChargeFuze/Model/ChargeAlertAttributes.swift field for field.
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

private let brand = Color(red: 0.0, green: 0.502, blue: 0.965)

@main
struct ChargeFuzeWidgets: WidgetBundle {
    var body: some Widget { LowBatteryLiveActivity(); RentalLiveActivity() }
}

/// Low battery shows OUTSIDE the app: a long Live Activity on the Lock Screen and in the Dynamic Island.
struct LowBatteryLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChargeAlertAttributes.self) { ctx in
            HStack(spacing: 14) {
                BatteryBadge(level: ctx.state.battery)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Phone at \(ctx.state.battery)% · charger \(ctx.state.minutes) min away").font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    Text("\(ctx.attributes.venue) · \(ctx.state.chargers) ready")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Link(destination: url(ctx)) {
                    Text("Get code").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(brand, in: .capsule)
                }
            }
            .padding(16)
            .activityBackgroundTint(.white.opacity(0.85))
            .activitySystemActionForegroundColor(brand)
            .widgetURL(url(ctx))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BatteryBadge(level: ctx.state.battery).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Phone at \(ctx.state.battery)% · charger \(ctx.state.minutes) min away").font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                        Text("\(ctx.attributes.venue) · \(ctx.state.chargers) ready")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Link(destination: url(ctx)) {
                        Text("Get code").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(brand, in: .capsule)
                    }
                }
            } compactLeading: {
                Image(systemName: "battery.25percent").foregroundStyle(.red)
            } compactTrailing: {
                Text("\(ctx.state.minutes) min").font(.caption.weight(.semibold)).foregroundStyle(brand)
            } minimal: {
                Image(systemName: "battery.25percent").foregroundStyle(.red)
            }
            .widgetURL(url(ctx))
            .keylineTint(.red)
        }
    }

    private func url(_ ctx: ActivityViewContext<ChargeAlertAttributes>) -> URL {
        URL(string: "chargefuze://quickrent/\(ctx.attributes.stationID)")!
    }
}

private struct BatteryBadge: View {
    let level: Int
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "battery.25percent").font(.title2).foregroundStyle(.red)
            Text("\(level)%").font(.caption.weight(.bold)).foregroundStyle(.red)
        }
    }
}

/// The running rental, outside the app: timer, cost so far, next charge, and a Return button.
struct RentalLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RentalAttributes.self) { ctx in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill").font(.caption.bold()).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(brand, in: .rect(cornerRadius: 6))
                    Text("Renting · \(ctx.attributes.venue)").font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Time").font(.caption).foregroundStyle(.secondary)
                        Text(timerInterval: ctx.attributes.startedAt...Date.distantFuture, countsDown: false)
                            .font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 0) {
                        Text("So far").font(.caption).foregroundStyle(.secondary)
                        Text(ctx.state.costSoFar, format: .currency(code: "USD"))
                            .font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(brand)
                    }
                    Spacer()
                    Link(destination: URL(string: "chargefuze://return/\(ctx.attributes.rentalID)")!) {
                        Text("Return").font(.subheadline.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 10).background(brand, in: .capsule)
                    }
                }
                if let next = ctx.state.nextChargeAt {
                    HStack(spacing: 4) {
                        Text("Next \(ctx.attributes.priceLabel.components(separatedBy: " ").first ?? "") in")
                        Text(timerInterval: Date.now...next, countsDown: true).monospacedDigit()
                        Text("· max \(ctx.attributes.dailyMax, format: .currency(code: "USD")) a day")
                    }
                    .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .activityBackgroundTint(.white.opacity(0.85))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text("Renting").font(.caption).foregroundStyle(.secondary)
                        Text(timerInterval: ctx.attributes.startedAt...Date.distantFuture, countsDown: false)
                            .font(.title2.bold()).monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Link(destination: URL(string: "chargefuze://return/\(ctx.attributes.rentalID)")!) {
                        Text("Return").font(.subheadline.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 9).background(brand, in: .capsule)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(ctx.state.costSoFar, format: .currency(code: "USD")) so far · \(ctx.attributes.venue)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "bolt.fill").foregroundStyle(.yellow)
            } compactTrailing: {
                Text(timerInterval: ctx.attributes.startedAt...Date.distantFuture, countsDown: false)
                    .monospacedDigit().frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "bolt.fill").foregroundStyle(.yellow)
            }
            .widgetURL(URL(string: "chargefuze://return/\(ctx.attributes.rentalID)"))
        }
    }
}
