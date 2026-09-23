import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Web's `CityInfoHeader`: city and country, the description, and the four
/// tiles (population, area, language, weather). Shimmers until city data lands.
struct ResultsHeader: View {
  let city: Loci_City_GeneralCityData?
  let fallbackCityName: String?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(city?.city ?? fallbackCityName ?? "Your trip").font(.lociDisplay(28)).foregroundStyle(Color.lociInk)
        if let city, !city.country.isEmpty {
          Text([city.stateProvince, city.country].filter { !$0.isEmpty }.joined(separator: ", ")).lociCoordStyle()
        }
      }
      if let city, !city.description_p.isEmpty {
        Text(city.description_p)
          .font(.lociBody(15)).foregroundStyle(Color.lociMutedInk)
          .transition(reduceMotion ? .identity : .opacity)
      }
      tiles
    }
    .animation(reduceMotion ? nil : LociTheme.reducedFade, value: city?.description_p)
  }

  private var tiles: some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
      CityTile(kicker: "Pop", value: city?.population ?? "", symbol: "person.2")
      CityTile(kicker: "Area", value: city?.area ?? "", symbol: "square.dashed")
      CityTile(kicker: "Lang", value: city?.language ?? "", symbol: "character.bubble")
      CityTile(kicker: "Weather", value: city?.weather ?? "", symbol: "cloud.sun")
    }
    .redacted(reason: city == nil ? .placeholder : [])
    .accessibilityLabel(city == nil ? "Loading city facts" : "City facts")
  }
}

private struct CityTile: View {
  let kicker: String
  let value: String
  let symbol: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: symbol).foregroundStyle(Color.lociForest).frame(width: 20)
      VStack(alignment: .leading, spacing: 1) {
        Text(kicker).lociCoordStyle(10)
        Text(value.isEmpty ? "N/A" : value).font(.lociCaption(13)).foregroundStyle(Color.lociInk).lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .background(Color.lociMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

/// Web's `LocalWeather` + `TripMoney`: weekday chips, alerts, one FX line.
struct LocalContextStrip: View {
  let context: Loci_Localcontext_LocalContext?
  let fxRates: [Loci_Localcontext_FxRate]

  var body: some View {
    if context != nil || !fxRates.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        if let context, !context.weather.isEmpty {
          HStack(spacing: 6) {
            Text("Next days").lociCoordStyle(10)
            if context.weatherIsEstimated {
              Text("estimated").lociCoordStyle(9)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.lociMuted, in: Capsule())
            }
          }
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(Array(context.weather.enumerated()), id: \.offset) { _, day in WeatherChip(day: day) }
            }
          }
          .scrollClipDisabled()
        }
        if let context, !context.alerts.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(context.alerts.enumerated()), id: \.offset) { _, alert in AlertRow(alert: alert) }
          }
        }
        if let line = FxLine.text(fxRates) {
          Label(line, systemImage: "coloncurrencysign.circle").font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
        }
      }
    }
  }
}

private struct WeatherChip: View {
  let day: Loci_Localcontext_WeatherDay

  var body: some View {
    VStack(spacing: 3) {
      Text(day.hasDate ? day.date.date.formatted(.dateTime.weekday(.abbreviated)) : "—").lociCoordStyle(10)
      Image(systemName: Self.symbol(for: day.condition)).foregroundStyle(Color.lociForest)
      Text("\(Int(day.highC.rounded()))° / \(Int(day.lowC.rounded()))°").font(.lociCaption(12)).foregroundStyle(Color.lociInk)
      if day.precipProb >= 0.3 {
        Text("\(Int((day.precipProb * 100).rounded()))% rain").font(.lociCaption(10)).foregroundStyle(Color.lociMutedInk)
      }
    }
    .frame(width: 64)
    .padding(.vertical, 8)
    .background(Color.lociMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  static func symbol(for condition: String) -> String {
    switch condition.lowercased() {
    case let c where c.contains("thunder"): "cloud.bolt.rain"
    case let c where c.contains("snow"): "cloud.snow"
    case let c where c.contains("rain") || c.contains("drizzle") || c.contains("shower"): "cloud.rain"
    case let c where c.contains("fog") || c.contains("mist"): "cloud.fog"
    case let c where c.contains("cloud") || c.contains("overcast"): "cloud"
    case let c where c.contains("part"): "cloud.sun"
    default: "sun.max"
    }
  }
}

private struct AlertRow: View {
  let alert: Loci_Localcontext_LocalAlert

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Circle().fill(LocalAlertStyle.color(severity: alert.severity)).frame(width: 8, height: 8).padding(.top, 5)
      VStack(alignment: .leading, spacing: 1) {
        Text(alert.title).font(.lociCaption(13)).foregroundStyle(Color.lociInk)
        if !alert.detail.isEmpty { Text(alert.detail).font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk).lineLimit(2) }
      }
    }
    .accessibilityElement(children: .combine)
  }
}

enum LocalAlertStyle {
  static func color(severity: Double) -> Color {
    if severity >= 0.7 { return .lociDestructive }
    if severity >= 0.4 { return .lociCoral }
    return .lociMutedInk
  }
}

nonisolated enum FxLine {
  /// "1 EUR = 1.07 USD · as of 23 Sep" from the first supported rate.
  static func text(_ rates: [Loci_Localcontext_FxRate]) -> String? {
    guard let first = rates.first(where: { $0.rate > 0 }) else { return nil }
    var line = "1 \(first.base) = \(first.rate.formatted(.number.precision(.fractionLength(2)))) \(first.quote)"
    if first.hasAsOf { line += " · as of \(first.asOf.date.formatted(.dateTime.day().month(.abbreviated)))" }
    return line
  }
}
