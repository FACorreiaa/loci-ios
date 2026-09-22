import Foundation

/// A destination with a reason to go this month. Same table as web's
/// `lib/dashboard/seasons.ts`; hooks follow the destination's own calendar,
/// so there is no hemisphere logic.
nonisolated struct SeasonalPick: Equatable, Sendable {
  let city: String
  /// ISO 3166-1 alpha-2, for the flag.
  let countryCode: String
  /// Months (1–12) the hook applies.
  let months: [Int]
  /// Reads after "for": "the harvest season", "Oktoberfest".
  let hook: String
  let emoji: String
  /// Trip length the prompt asks for.
  var days = 3

  /// The request the search box can send as-is (web: `promptFor`).
  var prompt: String { "Plan \(days) days in \(city) for \(hook)" }
}

nonisolated enum SeasonalPicks {
  static let all: [SeasonalPick] = [
    // January
    SeasonalPick(city: "Tromsø", countryCode: "NO", months: [1, 2, 11, 12], hook: "the northern lights", emoji: "🌌", days: 4),
    SeasonalPick(city: "Madeira", countryCode: "PT", months: [1, 2], hook: "a mild winter escape", emoji: "🌿"),
    SeasonalPick(city: "Seville", countryCode: "ES", months: [1, 2], hook: "the orange harvest", emoji: "🍊"),
    SeasonalPick(city: "Vienna", countryCode: "AT", months: [1], hook: "ball season", emoji: "🎻"),
    SeasonalPick(city: "Innsbruck", countryCode: "AT", months: [1, 2], hook: "a ski weekend", emoji: "⛷️"),
    // February
    SeasonalPick(city: "Venice", countryCode: "IT", months: [2], hook: "carnival", emoji: "🎭"),
    SeasonalPick(city: "Valencia", countryCode: "ES", months: [2, 3], hook: "Las Fallas", emoji: "🔥"),
    SeasonalPick(city: "Marrakech", countryCode: "MA", months: [2, 3, 11], hook: "the mild season", emoji: "🏺"),
    // March
    SeasonalPick(city: "Kyoto", countryCode: "JP", months: [3, 4], hook: "early blossom", emoji: "🌸", days: 5),
    SeasonalPick(city: "Lisbon", countryCode: "PT", months: [3, 4], hook: "the first spring light", emoji: "☀️"),
    SeasonalPick(city: "Dublin", countryCode: "IE", months: [3], hook: "St Patrick's week", emoji: "☘️"),
    SeasonalPick(city: "Rome", countryCode: "IT", months: [3, 4, 10], hook: "shoulder season", emoji: "🏛️"),
    // April
    SeasonalPick(city: "Amsterdam", countryCode: "NL", months: [4], hook: "tulip season", emoji: "🌷"),
    SeasonalPick(city: "Seville", countryCode: "ES", months: [4], hook: "Feria de Abril", emoji: "💃"),
    SeasonalPick(city: "Paris", countryCode: "FR", months: [4, 5], hook: "spring in the parks", emoji: "🥐"),
    SeasonalPick(city: "Istanbul", countryCode: "TR", months: [4, 5, 10], hook: "the tulip festival", emoji: "🕌"),
    // May
    SeasonalPick(city: "Lisbon", countryCode: "PT", months: [5, 6], hook: "the jacarandas", emoji: "💜"),
    SeasonalPick(city: "Porto", countryCode: "PT", months: [5, 6], hook: "São João", emoji: "🎈"),
    SeasonalPick(city: "Amalfi", countryCode: "IT", months: [5, 6, 9], hook: "the coast before the crowds", emoji: "🍋"),
    SeasonalPick(city: "Crete", countryCode: "GR", months: [5, 6, 9, 10], hook: "warm sea, quiet beaches", emoji: "🏖️", days: 5),
    // June
    SeasonalPick(city: "Reykjavik", countryCode: "IS", months: [6, 7], hook: "the midnight sun", emoji: "🌞", days: 4),
    SeasonalPick(city: "Stockholm", countryCode: "SE", months: [6], hook: "Midsummer", emoji: "🌼"),
    SeasonalPick(city: "Sintra", countryCode: "PT", months: [6, 7, 8], hook: "cool hills above Lisbon", emoji: "🏰"),
    // July
    SeasonalPick(city: "Dubrovnik", countryCode: "HR", months: [7, 8], hook: "the summer festival", emoji: "🎪"),
    SeasonalPick(city: "Avignon", countryCode: "FR", months: [7], hook: "the theatre festival", emoji: "🎟️"),
    SeasonalPick(city: "Bergen", countryCode: "NO", months: [7, 8], hook: "long fjord days", emoji: "⛰️", days: 4),
    SeasonalPick(city: "Azores", countryCode: "PT", months: [7, 8, 9], hook: "hydrangeas and whales", emoji: "🐋", days: 5),
    // August
    SeasonalPick(city: "Edinburgh", countryCode: "GB", months: [8], hook: "the Fringe", emoji: "🎤", days: 4),
    SeasonalPick(city: "Salzburg", countryCode: "AT", months: [8], hook: "the summer festival", emoji: "🎼"),
    SeasonalPick(city: "San Sebastián", countryCode: "ES", months: [8, 9], hook: "Semana Grande and pintxos", emoji: "🍢"),
    // September
    SeasonalPick(city: "Porto", countryCode: "PT", months: [9, 10], hook: "the harvest season", emoji: "🍇"),
    SeasonalPick(city: "Munich", countryCode: "DE", months: [9, 10], hook: "Oktoberfest", emoji: "🍺"),
    SeasonalPick(city: "Ljubljana", countryCode: "SI", months: [9, 10], hook: "the golden hour", emoji: "🍂"),
    SeasonalPick(city: "Bordeaux", countryCode: "FR", months: [9, 10], hook: "the vendanges", emoji: "🍷"),
    SeasonalPick(city: "Barcelona", countryCode: "ES", months: [9], hook: "La Mercè", emoji: "🎆"),
    // October
    SeasonalPick(city: "Douro Valley", countryCode: "PT", months: [10], hook: "the grape harvest", emoji: "🍇", days: 2),
    SeasonalPick(city: "Boston", countryCode: "US", months: [10], hook: "New England foliage", emoji: "🍁", days: 5),
    SeasonalPick(city: "Alsace", countryCode: "FR", months: [10, 11], hook: "wine villages in autumn", emoji: "🍂"),
    // November
    SeasonalPick(city: "Madrid", countryCode: "ES", months: [11], hook: "the museum season", emoji: "🖼️"),
    SeasonalPick(city: "Bruges", countryCode: "BE", months: [11, 12], hook: "misty canals", emoji: "🍫"),
    SeasonalPick(city: "Malta", countryCode: "MT", months: [11], hook: "late sun", emoji: "🌅", days: 4),
    // December
    SeasonalPick(city: "Vienna", countryCode: "AT", months: [12], hook: "the Christmas markets", emoji: "🎄"),
    SeasonalPick(city: "Strasbourg", countryCode: "FR", months: [12], hook: "the Christmas market", emoji: "⭐"),
    SeasonalPick(city: "Copenhagen", countryCode: "DK", months: [12], hook: "hygge season", emoji: "🕯️"),
  ]

  /// Picks for a month (1–12), in table order.
  static func picks(forMonth month: Int) -> [SeasonalPick] { all.filter { $0.months.contains(month) } }

  /// 🇵🇹 from "PT"; empty for anything that is not two letters.
  static func flag(for code: String) -> String {
    let letters = code.uppercased().unicodeScalars
    guard letters.count == 2, letters.allSatisfy({ ("A"..."Z").contains(Character($0)) }) else { return "" }
    return String(String.UnicodeScalarView(letters.compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 65) }))
  }
}

/// One chip on the strip (web: `InSeasonItem`).
nonisolated struct InSeasonItem: Identifiable, Equatable, Sendable {
  /// "season:porto" or "trending:funchal".
  let id: String
  let city: String
  let countryCode: String
  let emoji: String
  let hook: String
  /// Sessions this week for the city; 0 when nobody asked.
  let planned: Int
  let prompt: String

  var flag: String { SeasonalPicks.flag(for: countryCode) }
}

/// A city people asked about this week (DiscoverService.GetTrending).
nonisolated struct InSeasonTrending: Equatable, Sendable {
  let cityName: String
  let searchCount: Int
  let emoji: String
}

nonisolated enum InSeason {
  static let maxItems = 12

  private static func key(_ city: String) -> String { city.trimmingCharacters(in: .whitespaces).lowercased() }

  /// Merge the curated picks with this week's trending cities, exactly as web's
  /// `buildInSeasonItems`: planned picks first, then the rest of the table,
  /// then trending cities that are not in season; no repeated ids; capped.
  static func items(picks: [SeasonalPick], trending: [InSeasonTrending]?, max: Int = maxItems) -> [InSeasonItem] {
    var planned: [String: InSeasonTrending] = [:]
    var plannedOrder: [String] = []
    for entry in trending ?? [] {
      let k = key(entry.cityName)
      if !k.isEmpty, planned[k] == nil {
        planned[k] = entry
        plannedOrder.append(k)
      }
    }

    let seasonal = picks.map { pick in
      InSeasonItem(
        id: "season:\(key(pick.city))",
        city: pick.city,
        countryCode: pick.countryCode,
        emoji: pick.emoji,
        hook: pick.hook,
        planned: planned[key(pick.city)]?.searchCount ?? 0,
        prompt: pick.prompt
      )
    }
    let withPlans = seasonal.filter { $0.planned > 0 }
    let without = seasonal.filter { $0.planned == 0 }

    let inSeason = Set(picks.map { key($0.city) })
    let extra = plannedOrder.compactMap { k -> InSeasonItem? in
      guard !inSeason.contains(k), let entry = planned[k] else { return nil }
      let city = entry.cityName.trimmingCharacters(in: .whitespaces)
      return InSeasonItem(
        id: "trending:\(k)",
        city: city,
        countryCode: "",
        emoji: entry.emoji,
        hook: "planned this week",
        planned: entry.searchCount,
        prompt: "Plan 3 days in \(city)"
      )
    }

    var seen = Set<String>()
    return Array((withPlans + without + extra).filter { seen.insert($0.id).inserted }.prefix(max))
  }

  /// One loop of the strip: slow enough to read, longer with more items.
  static func loopDuration(count: Int) -> TimeInterval { max(30, Double(count) * 6) }

  /// Fewer items than this fit in a row; moving them would look broken.
  static func needsMarquee(count: Int) -> Bool { count >= 5 }

  static func monthLabel(_ date: Date = Date(), calendar: Calendar = .current) -> String {
    calendar.monthSymbols[calendar.component(.month, from: date) - 1]
  }
}
