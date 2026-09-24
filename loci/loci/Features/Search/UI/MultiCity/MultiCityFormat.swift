import Foundation
import LociConnectProto

/// The strings web renders for a multi-city trip (loci-client multi-city-view.ts),
/// so both apps read alike.
nonisolated enum MultiCityFormat {
  /// "Train · ≈3h14 · 274 km" — an estimate, and it says so.
  static func leg(_ leg: Loci_Trip_TripLeg) -> String {
    let mode = ["drive": "Drive", "train": "Train", "bus": "Bus", "flight": "Flight"][leg.mode] ?? "Travel"
    let mins = Int(leg.durationMins)
    let time = mins < 60 ? "\(mins) min" : "\(mins / 60)h" + String(format: "%02d", mins % 60)
    return "\(mode) · ≈\(time) · \(Int(leg.distanceKm.rounded())) km"
  }

  /// "Lisbon · 2n"
  static func chip(_ stop: StopResult) -> String { "\(stop.cityName) · \(stop.dayNumbers.count)n" }

  /// The SF Symbol for a leg's mode.
  static func symbol(_ leg: Loci_Trip_TripLeg) -> String {
    switch leg.mode {
    case "train": "tram.fill"
    case "bus": "bus.fill"
    case "flight": "airplane"
    default: "car.fill"
    }
  }
}
