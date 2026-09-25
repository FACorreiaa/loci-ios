import SwiftUI

/// Cities, countries, places and distance (web: StatsRail). Every figure is a
/// count of real visits; the arrow is the change since the start of the
/// period and is left off when there was nothing to compare with.
struct TravelStatsCard: View {
  let summary: TravelSummary

  private struct Stat: Identifiable {
    let id: String
    let value: String
    let trend: Double?
    var hint: String?
  }

  private var stats: [Stat] {
    let s = summary
    let noCountry = s.citiesVisited > 0 && s.countriesVisited == 0
    let cities = Stat(
      id: "Cities",
      value: count(s.citiesVisited),
      trend: GlobeFormat.trendPercent(current: s.citiesVisited, previous: s.citiesVisitedPrev)
    )
    // Country is only known where a city resolved against the cities table.
    let countries = Stat(
      id: "Countries",
      value: count(s.countriesVisited),
      trend: GlobeFormat.trendPercent(current: s.countriesVisited, previous: s.countriesVisitedPrev),
      hint: noCountry ? "No country recorded yet" : nil
    )
    let places = Stat(id: "Places", value: count(s.poisVisited), trend: GlobeFormat.trendPercent(current: s.poisVisited, previous: s.poisVisitedPrev))
    let distance = Stat(id: "Distance", value: GlobeFormat.distance(s.distanceKm), trend: nil)
    return [cities, countries, places, distance]
  }

  private func count(_ value: Int) -> String { GlobeFormat.number(Double(value)) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Your travels").lociCoordStyle(10)
      LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], spacing: 14) {
        ForEach(stats) { stat in StatCell(label: stat.id, value: stat.value, trend: stat.trend, hint: stat.hint, periodDays: summary.periodDays) }
      }
    }.frame(maxWidth: .infinity, alignment: .leading).lociCard()
  }
}

private struct StatCell: View {
  let label: String
  let value: String
  let trend: Double?
  let hint: String?
  let periodDays: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label).font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(value).font(.lociTitle(24)).monospacedDigit().foregroundStyle(Color.lociInk).lineLimit(1).minimumScaleFactor(0.6)
        if let trend { TrendBadge(percent: trend) }
      }
      if let hint { Text(hint).font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk).fixedSize(horizontal: false, vertical: true) }
    }.accessibilityElement(children: .ignore).accessibilityLabel(accessibilityText)
  }

  private var accessibilityText: String {
    var text = "\(label): \(value)"
    if let trend { text += ", \(GlobeFormat.trendText(trend)) compared with \(periodDays) days ago" }
    if let hint { text += ". \(hint)" }
    return text
  }
}

private struct TrendBadge: View {
  let percent: Double

  var body: some View {
    let up = percent >= 0
    HStack(spacing: 1) {
      Image(systemName: up ? "arrow.up.right" : "arrow.down.right").accessibilityHidden(true)
      Text(GlobeFormat.trendText(percent)).monospacedDigit()
    }.font(.lociCaption(11).weight(.semibold)).foregroundStyle(up ? Color.lociForest : Color.lociMutedInk)
  }
}
