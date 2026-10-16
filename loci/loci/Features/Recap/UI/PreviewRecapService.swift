import Foundation
import LociConnectProto

/// Offline sample data for `-designPreview recap` and `sharedRecap`: five days
/// in Lisbon with something on every card.
nonisolated struct PreviewRecapService: RecapService {
  func tripRecap(tripID: String, refresh: Bool) async throws -> Loci_Recap_Recap { .previewLisbon }
  func sharedRecap(code: String) async throws -> Loci_Recap_Recap { .previewLisbonPublic }
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
}
