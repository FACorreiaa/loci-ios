import Foundation
import LociConnectProto
import Testing

@testable import loci

struct TasteFencesTests {
  private func saved(_ id: String, city: String = "Lisbon", score: Float? = 0.8, lat: Double = 38.71, lon: Double = -9.14) -> Loci_Favorites_V1_FavoriteItem {
    var f = Loci_Favorites_V1_FavoriteItem()
    f.itemID = id
    f.itemName = id
    f.cityName = city
    f.contentType = .poi
    f.latitude = lat
    f.longitude = lon
    if let score {
      var m = Loci_Poi_TasteMatch()
      m.score = score
      f.tasteMatch = m
    }
    return f
  }

  @Test func picksTopFitsInCity() {
    let favorites = [
      saved("ok", score: 0.7), saved("best", score: 0.95), saved("weak", score: 0.4), saved("unscored", score: nil),
      saved("porto", city: "Porto", score: 0.99), saved("spaced", city: "  lisbon ", score: 0.8),
    ]
    #expect(TasteFencePlan.pick(favorites, city: "Lisbon", budget: 20).map(\.itemID) == ["best", "spaced", "ok"])
  }

  @Test func skipsNoCoordinates() {
    let favorites = [saved("nowhere", lat: 0, lon: 0), saved("here")]
    #expect(TasteFencePlan.pick(favorites, city: "Lisbon", budget: 20).map(\.itemID) == ["here"])
  }

  @Test func respectsBudget() {
    let favorites = (0..<30).map { saved("p\($0)", score: 0.6 + Float($0) / 100) }
    #expect(TasteFencePlan.pick(favorites, city: "Lisbon", budget: 20).count == 15)
    #expect(TasteFencePlan.pick(favorites, city: "Lisbon", budget: 4).map(\.itemID) == ["p29", "p28", "p27", "p26"])
    #expect(TasteFencePlan.pick(favorites, city: "Lisbon", budget: 0).isEmpty)
  }

  /// A walk or a trip day takes the fences it needs; the taste fences get what is left.
  @Test func fencesYieldToWalk() {
    var budget = FenceBudget()
    #expect(budget.available(for: TasteFences.name) == 20)
    budget.used[POIProximityMonitor.nearbyWalkName] = 12
    budget.used[TasteFences.name] = 15
    #expect(budget.available(for: TasteFences.name) == 8)
    budget.used[POIProximityMonitor.tripDayName] = 10
    #expect(budget.available(for: TasteFences.name) == 0)
  }

  /// CLMonitor keeps a walk's conditions across launches, so the count it
  /// holds must survive the process too.
  @Test func budgetSurvivesRelaunch() {
    let saved = UserDefaults.standard.object(forKey: TasteFences.budgetKey)
    defer { UserDefaults.standard.set(saved, forKey: TasteFences.budgetKey) }
    TasteFences.budget = FenceBudget(used: [POIProximityMonitor.nearbyWalkName: 12])
    let reread = FenceBudget(used: UserDefaults.standard.dictionary(forKey: TasteFences.budgetKey) as? [String: Int] ?? [:])
    #expect(reread.available(for: TasteFences.name) == 8)
  }

  private func limiter() throws -> NudgeLimiter {
    let suite = "taste-fences-\(UUID().uuidString)"
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try #require(TimeZone(identifier: "UTC"))
    return NudgeLimiter(defaults: try #require(UserDefaults(suiteName: suite)), calendar: utc)
  }

  private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try #require(TimeZone(identifier: "UTC"))
    return try #require(utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
  }

  @Test func limiterTwoPerDay() throws {
    let l = try limiter()
    #expect(l.allow(poiID: "a", now: try at(20, 10)))
    #expect(l.allow(poiID: "b", now: try at(20, 12)))
    #expect(!l.allow(poiID: "c", now: try at(20, 15)))
    #expect(l.allow(poiID: "c", now: try at(21, 9)))
  }

  @Test func limiterQuietHours() throws {
    let l = try limiter()
    #expect(!l.allow(poiID: "a", now: try at(20, 7, 59)))
    #expect(!l.allow(poiID: "a", now: try at(20, 21)))
    #expect(l.allow(poiID: "a", now: try at(20, 8)))
  }

  @Test func limiterOncePerWeekPerPlace() throws {
    let l = try limiter()
    #expect(l.allow(poiID: "a", now: try at(1, 10)))
    #expect(!l.allow(poiID: "a", now: try at(7, 10)))
    #expect(l.allow(poiID: "a", now: try at(8, 10, 1)))
  }
}
