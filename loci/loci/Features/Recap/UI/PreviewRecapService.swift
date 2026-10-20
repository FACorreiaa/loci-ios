import Foundation
import LociConnectProto

/// Offline sample data for `-designPreview recap` and `sharedRecap` (five days
/// in Lisbon with something on every card), and `yearRecap` and
/// `sharedYearRecap` (a 2026 with every year card).
nonisolated struct PreviewRecapService: RecapService {
  /// Whether a shared link opens the year rather than the trip.
  var sharesYear = false

  func tripRecap(tripID: String, refresh: Bool) async throws -> Loci_Recap_Recap { .previewLisbon }
  func yearInReview(year: Int) async throws -> Loci_Recap_Recap { .previewYear }
  func sharedRecap(code: String) async throws -> Loci_Recap_Recap { sharesYear ? .previewYearPublic : .previewLisbonPublic }
  func share(recapID: String) async throws -> URL { URL(string: "https://lociai.fyi/r/preview") ?? URL(fileURLWithPath: "/") }
  func markViewed(recapID: String) async {}
  func cardImage(recapID: String, cardID: String) async throws -> Data { throw APIError.server("Images need the server.") }
}

extension Loci_Recap_Recap {
  static var previewLisbon: Loci_Recap_Recap {
    var r = Loci_Recap_Recap()
    r.id = "preview"
    r.status = .ready
    r.kind = .trip
    r.title = "Lisbon"
    r.subtitle = "5 days · Oct 2026"
    r.periodLabel = "Oct 2026"
    r.isOwner = true

    func card(_ id: String, _ body: Loci_Recap_RecapCard.OneOf_Card) -> Loci_Recap_RecapCard {
      var c = Loci_Recap_RecapCard()
      c.id = id
      c.card = body
      return c
    }

    var intro = Loci_Recap_IntroCard()
    intro.lede = "Five days in Lisbon, and the shoes to prove it."
    intro.shortCode = "LIS"
    intro.primaryCity = "Lisbon"
    intro.country = "Portugal"
    intro.dayCount = 5

    var places = Loci_Recap_PlacesCard()
    places.placesCount = 23
    places.citiesCount = 1
    places.headline = "Kept across five neighbourhoods. Alfama took the most stamps."
    places.groups = [
      ("Alfama", 9, "2026-10-11"), ("Baixa", 5, "2026-10-12"), ("Belém", 4, "2026-10-13"), ("Príncipe Real", 3, ""), ("LX Factory", 2, ""),
    ].map { label, count, date in
      var g = Loci_Recap_PlaceGroup()
      g.label = label
      g.placesCount = Int32(count)
      g.firstDate = date
      return g
    }

    var route = Loci_Recap_RouteCard()
    route.distanceKm = 41.2
    route.basis = .visits
    route.headline = "From Miradouro de Santa Luzia to Jerónimos."
    route.points = [
      (38.7118, -9.1300, "Miradouro de Santa Luzia"), (38.7120, -9.1330, "Tasca"), (38.7107, -9.1416, "Brasileira"), (38.7140, -9.1590, "Senhor Uva"),
      (38.6979, -9.2061, "Jerónimos"),
    ].map { lat, lon, label in
      var p = Loci_Recap_RoutePoint()
      p.latitude = lat
      p.longitude = lon
      p.label = label
      return p
    }

    var days = Loci_Recap_DaysCard()
    days.daysTotal = 5
    days.daysCompleted = 4
    days.busiestDayNumber = 2
    days.headline = "4 of 5 days walked to the end."
    days.days = (1...5).map { n in
      var d = Loci_Recap_DayStub()
      d.dayNumber = Int32(n)
      d.stopsDone = Int32([4, 6, 3, 5, 1][n - 1])
      d.completed = n < 5
      return d
    }

    var taste = Loci_Recap_TasteCard()
    taste.fromPeriod = true
    taste.headline = "You kept going back to natural wine bars."
    taste.traits = [
      ("Natural wine bars", 1.0, 7, Loci_Recap_TasteEvidenceKind.saves, Loci_Recap_TasteTrend.strong),
      ("Tiled, older streets", 0.7, 5, .visits, .growing), ("Long riverside lunches", 0.48, 3, .visits, .new),
    ].map { label, strength, count, kind, trend in
      var t = Loci_Recap_TasteTrait()
      t.label = label
      t.strength = strength
      t.evidenceCount = Int32(count)
      t.evidenceKind = kind
      t.trend = trend
      return t
    }

    var highlights = Loci_Recap_HighlightsCard()
    highlights.headline = "The ones you kept."
    highlights.highlights = [
      ("Senhor Uva", "wine bar", 5, Loci_Recap_HighlightReason.reviewed), ("Miradouro de Santa Luzia", "viewpoint", 0, .firstVisit),
      ("Pastéis de Belém", "bakery", 0, .favorited),
    ].map { name, category, rating, reason in
      var h = Loci_Recap_Highlight()
      h.name = name
      h.category = category
      h.rating = Int32(rating)
      h.reason = reason
      return h
    }

    var progress = Loci_Recap_ProgressCard()
    progress.points = 184
    progress.streakDays = 5
    progress.headline = "184 points and 2 badges on this trip."
    progress.badges = [("first-city", "First city"), ("trip-finisher", "Trip finisher")].map { id, label in
      var b = Loci_Recap_EarnedBadge()
      b.badgeID = id
      b.label = label
      return b
    }

    var field = Loci_Recap_FieldCard()
    field.cityName = "Lisbon"
    field.score = 140
    field.rankLabel = "Guide"
    field.placesKept = 6
    field.daysFinished = 4
    field.headline = "Guide of Lisbon."

    var friends = Loci_Recap_FriendsCard()
    friends.friendsBeenCount = 2
    friends.headline = "Two of your friends have Lisbon on a trip too."
    friends.friends = ["Ana Sousa", "Rui Lopes"].map {
      var f = Loci_Recap_FriendRef()
      f.displayName = $0
      return f
    }

    var outro = Loci_Recap_OutroCard()
    outro.headline = "Where to next?"
    outro.summaryLine = "23 places · 41 km · 5 days"

    r.cards = [
      card("intro", .intro(intro)), card("places", .places(places)), card("route", .route(route)), card("days", .days(days)),
      card("taste", .taste(taste)), card("highlights", .highlights(highlights)), card("progress", .progress(progress)), card("field", .field(field)),
      card("friends", .friends(friends)), card("outro", .outro(outro)),
    ]
    return r
  }

  /// What a stranger sees: no highlights, no stamps but the city, no friends' names.
  static var previewLisbonPublic: Loci_Recap_Recap {
    var r = previewLisbon
    r.isOwner = false
    r.cards = r.cards.compactMap { c in
      var c = c
      switch c.card {
      case .highlights: return nil
      case .places(var p):
        var g = Loci_Recap_PlaceGroup()
        g.label = "Lisbon"
        g.placesCount = p.placesCount
        p.groups = [g]
        p.headline = "Kept across five neighbourhoods of Lisbon."
        c.card = .places(p)
      case .route(var rt):
        rt.points = []
        rt.headline = ""
        c.card = .route(rt)
      case .friends(var f):
        f.friends = []
        f.headline = ""
        c.card = .friends(f)
      default: break
      }
      return c
    }
    return r
  }

  /// A 2026 of three trips across Portugal, Spain and a first time in Morocco.
  nonisolated static var previewYear: Loci_Recap_Recap {
    var r = Loci_Recap_Recap()
    r.id = "preview-year"
    r.status = .ready
    r.kind = .year
    r.year = 2026
    r.title = "Your 2026"
    r.subtitle = "4 trips · 6 cities"
    r.periodLabel = "2026"
    r.isOwner = true

    func card(_ id: String, _ body: Loci_Recap_RecapCard.OneOf_Card) -> Loci_Recap_RecapCard {
      var c = Loci_Recap_RecapCard()
      c.id = id
      c.card = body
      return c
    }
    func point(_ lat: Double, _ lon: Double, _ label: String) -> Loci_Recap_RoutePoint {
      var p = Loci_Recap_RoutePoint()
      p.latitude = lat
      p.longitude = lon
      p.label = label
      return p
    }

    var intro = Loci_Recap_IntroCard()
    intro.lede = "Four trips, six cities, one year."
    intro.shortCode = "'26"
    intro.primaryCity = "Lisbon"
    intro.country = "Portugal"
    intro.dayCount = 18
    intro.cityNames = ["Lisbon", "Madrid", "Porto", "Marrakesh", "Faro", "Barcelona"]

    var map = Loci_Recap_YearMapCard()
    map.countriesCount = 3
    map.citiesCount = 6
    map.newCountriesCount = 1
    map.headline = "Six cities in three countries, one of them new to you."
    let countries = [("Portugal", "PT", 3, 11, false), ("Spain", "ES", 2, 5, false), ("Morocco", "MA", 1, 2, true)]
    map.countries = countries.map { name, code, cities, days, first in
      var c = Loci_Recap_YearCountry()
      c.country = name
      c.countryCode = code
      c.citiesCount = Int32(cities)
      c.days = Int32(days)
      c.firstTime = first
      return c
    }
    map.cities = [
      point(38.72, -9.14, "Lisbon"), point(40.42, -3.70, "Madrid"), point(41.15, -8.61, "Porto"), point(31.63, -8.01, "Marrakesh"),
      point(37.02, -7.93, "Faro"), point(41.39, 2.17, "Barcelona"),
    ]

    var timeline = Loci_Recap_TripsTimelineCard()
    timeline.tripsCount = 4
    timeline.daysAway = 18
    timeline.busiestMonth = 6
    timeline.headline = "4 trips, 18 days away. June was the busiest."
    let byMonth: [Int: (Int, Int)] = [3: (1, 4), 6: (2, 9), 10: (1, 5)]
    timeline.months = (1...12).map { m in
      var month = Loci_Recap_TimelineMonth()
      month.month = Int32(m)
      month.tripsCount = Int32(byMonth[m]?.0 ?? 0)
      month.days = Int32(byMonth[m]?.1 ?? 0)
      return month
    }
    timeline.trips = [(3, "Porto", 4), (6, "Madrid", 5), (6, "Marrakesh", 4), (10, "Lisbon", 5)].map { month, city, days in
      var t = Loci_Recap_TimelineTrip()
      t.tripID = "t-\(city)"
      t.month = Int32(month)
      t.cityName = city
      t.dayCount = Int32(days)
      return t
    }

    var top = Loci_Recap_TopCityCard()
    top.cityID = "c-lisbon"
    top.cityName = "Lisbon"
    top.country = "Portugal"
    top.countryCode = "PT"
    top.days = 9
    top.placesCount = 41
    top.tripsCount = 2
    top.headline = "Lisbon was your city this year: 9 days and 41 places."

    var places = Loci_Recap_PlacesCard()
    places.placesCount = 87
    places.citiesCount = 6
    places.headline = "Kept across six cities. Lisbon took the most stamps."
    places.groups = [("Lisbon", 41), ("Madrid", 17), ("Porto", 12), ("Marrakesh", 9), ("Barcelona", 5), ("Faro", 3)].map { label, count in
      var g = Loci_Recap_PlaceGroup()
      g.label = label
      g.placesCount = Int32(count)
      return g
    }

    var shift = Loci_Recap_TasteShiftCard()
    shift.headline = "2026 was the year you got into natural wine bars."
    shift.strengthStart = 0.22
    shift.strengthEnd = 1
    func trait(_ label: String, _ strength: Double, _ evidence: Int32, _ trend: Loci_Recap_TasteTrend) -> Loci_Recap_TasteTrait {
      var t = Loci_Recap_TasteTrait()
      t.label = label
      t.strength = strength
      t.evidenceCount = evidence
      t.trend = trend
      return t
    }
    shift.trait = trait("Natural wine bars", 1, 14, .strong)
    shift.runnersUp = [trait("Tiled, older streets", 0.6, 6, .growing), trait("Bookshops", 0.3, 3, .new)]

    var streak = Loci_Recap_StreakCard()
    streak.longestStreakDays = 9
    streak.longestStreakStart = "2026-06-08"
    streak.longestStreakEnd = "2026-06-16"
    streak.activeDays = 64
    streak.bestMonth = 6
    streak.headline = "9 days in a row in June, and 64 active days in all."

    var progress = Loci_Recap_ProgressCard()
    progress.points = 2140
    progress.headline = "2,140 points and 3 badges this year."
    progress.badges = [("first-city", "First city"), ("trip-finisher", "Trip finisher"), ("globetrotter", "Globetrotter")].map { id, label in
      var b = Loci_Recap_EarnedBadge()
      b.badgeID = id
      b.label = label
      return b
    }

    var gave = Loci_Recap_ContributionsCard()
    gave.reviewsCount = 12
    gave.listsCount = 3
    gave.submissionsCount = 2
    gave.headline = "You gave back: 12 reviews, 3 lists and 2 places added."

    var pct = Loci_Recap_PercentileCard()
    pct.topPercent = 5
    pct.metric = .places
    pct.value = 87
    pct.headline = "Top 5% of Loci travellers for places kept."

    var outro = Loci_Recap_OutroCard()
    outro.headline = "See you in 2027."
    outro.summaryLine = "6 cities · 4 trips · 87 places"

    r.cards = [
      card("intro", .intro(intro)), card("year_map", .yearMap(map)), card("trips_timeline", .tripsTimeline(timeline)),
      card("top_city", .topCity(top)), card("places", .places(places)), card("taste_shift", .tasteShift(shift)),
      card("streak", .streak(streak)), card("progress", .progress(progress)),
      card("contributions", .contributions(gave)), card("percentile", .percentile(pct)), card("outro", .outro(outro)),
    ]
    return r
  }

  /// The year as a stranger sees it, as the server redacts it: no trip or
  /// city ids, no streak dates, no evidence counts.
  nonisolated static var previewYearPublic: Loci_Recap_Recap {
    var r = previewYear
    r.isOwner = false
    r.cards = r.cards.map { c in
      var c = c
      switch c.card {
      case .tripsTimeline(var t):
        t.trips = t.trips.map {
          var trip = $0
          trip.tripID = ""
          return trip
        }
        c.card = .tripsTimeline(t)
      case .topCity(var t):
        t.cityID = ""
        c.card = .topCity(t)
      case .streak(var s):
        s.longestStreakStart = ""
        s.longestStreakEnd = ""
        c.card = .streak(s)
      case .tasteShift(var t):
        t.trait.evidenceCount = 0
        t.runnersUp = t.runnersUp.map {
          var trait = $0
          trait.evidenceCount = 0
          return trait
        }
        c.card = .tasteShift(t)
      default: break
      }
      return c
    }
    return r
  }
}
