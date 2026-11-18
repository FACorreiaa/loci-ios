import Foundation
import LociConnectProto

/// How a public transport stop is written, on a hotel report and on the trip
/// page alike. The stops come from OpenStreetMap: what is there, never when
/// it runs.
nonisolated enum TransitFormat {
  static func modeLabel(_ mode: Loci_Trip_TransitMode) -> String {
    switch mode {
    case .metro: String(localized: "Metro")
    case .train: String(localized: "Train")
    case .tram: String(localized: "Tram")
    case .bus: String(localized: "Bus")
    case .ferry: String(localized: "Ferry")
    default: String(localized: "Stop")
    }
  }

  static func modeSymbol(_ mode: Loci_Trip_TransitMode) -> String {
    switch mode {
    case .metro: "tram.fill.tunnel"
    case .train: "train.side.front.car"
    case .tram: "tram.fill"
    case .bus: "bus.fill"
    case .ferry: "ferry.fill"
    default: "mappin.and.ellipse"
    }
  }

  static func distance(_ metres: Int32) -> String {
    metres >= 1000
      ? String(localized: "\((Double(metres) / 1000).formatted(.number.precision(.fractionLength(1)))) km") : String(localized: "\(metres) m")
  }

  /// "6 min walk", or the distance when the server sent no minutes. Nil when
  /// it sent neither.
  static func walk(minutes: Int32, metres: Int32) -> String? {
    if minutes > 0 { return String(localized: "\(minutes) min walk") }
    return metres > 0 ? distance(metres) : nil
  }

  /// "Fontana · L3 · 6 min walk", with "(estimate)" when the walk is a
  /// straight line rather than a routed one.
  static func stopLine(_ stop: Loci_Trip_TransitStop) -> String {
    parts(stop, estimate: String(localized: "(estimate)")).joined(separator: " · ")
  }

  /// The same for VoiceOver: commas for the dots, and the estimate spelt out.
  static func spokenStopLine(_ stop: Loci_Trip_TransitStop) -> String {
    parts(stop, estimate: String(localized: "a straight-line estimate")).joined(separator: ", ")
  }

  private static func parts(_ stop: Loci_Trip_TransitStop, estimate: String) -> [String] {
    let name = stop.name.trimmingCharacters(in: .whitespacesAndNewlines)
    var parts = [name.isEmpty ? String(localized: "Unnamed stop") : name]
    let lines = stop.lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    if !lines.isEmpty { parts.append(lines.joined(separator: ", ")) }
    if let walk = walk(minutes: stop.walkMinutes, metres: stop.distanceM) {
      parts.append(stop.routed ? walk : "\(walk) \(estimate)")
    }
    return parts
  }

  /// A link the server or a web page handed over, opened only when it is a
  /// plain https address with a host. Anything else stays text.
  static func httpsURL(_ text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https", let host = url.host(), !host.isEmpty else { return nil }
    return url
  }
}
