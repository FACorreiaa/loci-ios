import Foundation
import LociConnectProto

/// The strings web renders for a multi-city trip (loci-client multi-city-view.ts),
/// in the same shape, with the time and distance in the phone's locale.
nonisolated enum MultiCityFormat {
  /// "Train · ≈3h 14m · 274 km" — an estimate, and it says so.
  static func leg(_ leg: Loci_Trip_TripLeg, locale: Locale = .autoupdatingCurrent) -> String {
    let mode = ["drive": "Drive", "train": "Train", "bus": "Bus", "flight": "Flight"][leg.mode] ?? "Travel"
    let time = Duration.seconds(Int(leg.durationMins) * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow).locale(locale))
    let distance = Measurement(value: leg.distanceKm, unit: UnitLength.kilometers)
      .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
    return "\(mode) · ≈\(time) · \(distance)"
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
