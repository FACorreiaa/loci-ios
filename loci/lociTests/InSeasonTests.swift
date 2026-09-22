import Foundation
import Testing

@testable import loci

/// Mirrors web's lib/dashboard/in-season.test.ts.
struct InSeasonTests {
  private let porto = SeasonalPick(city: "Porto", countryCode: "PT", months: [9], hook: "the harvest season", emoji: "🍇")
  private let munich = SeasonalPick(city: "Munich", countryCode: "DE", months: [9], hook: "Oktoberfest", emoji: "🍺")
  private let ljubljana = SeasonalPick(city: "Ljubljana", countryCode: "SI", months: [9], hook: "the golden hour", emoji: "🍂")

  @Test func curatedPicksAloneWhenTrendingHasNotArrived() {
    let items = InSeason.items(picks: [porto, munich], trending: nil)
    #expect(items.map(\.id) == ["season:porto", "season:munich"])
    #expect(items[0].prompt == "Plan 3 days in Porto for the harvest season")
    #expect(items.allSatisfy { $0.planned == 0 })
  }

  @Test func matchesTrendingIgnoringCaseAndWhitespace() {
    let items = InSeason.items(picks: [porto], trending: [InSeasonTrending(cityName: "  pORTO ", searchCount: 7, emoji: "🇵🇹")])
    #expect(items.first?.planned == 7)
  }

  @Test func plannedPicksComeFirstKeepingTableOrderOtherwise() {
    let items = InSeason.items(picks: [porto, munich, ljubljana], trending: [InSeasonTrending(cityName: "Ljubljana", searchCount: 2, emoji: "")])
    #expect(items.map(\.city) == ["Ljubljana", "Porto", "Munich"])
  }

  @Test func appendsTrendingCitiesNotInSeasonAfterThePicks() {
    let items = InSeason.items(picks: [porto], trending: [InSeasonTrending(cityName: "Funchal", searchCount: 3, emoji: "🌺")])
    #expect(items.map(\.id) == ["season:porto", "trending:funchal"])
    #expect(items[1].hook == "planned this week")
    #expect(items[1].prompt == "Plan 3 days in Funchal")
    #expect(items[1].flag.isEmpty)
  }

  @Test func skipsTrendingRowsWithNoCityName() {
    let items = InSeason.items(picks: [porto], trending: [InSeasonTrending(cityName: "  ", searchCount: 3, emoji: "")])
    #expect(items.count == 1)
  }

  @Test func capsTheListAndNeverRepeatsAnId() {
    let picks = (0..<20).map { SeasonalPick(city: "City \($0)", countryCode: "PT", months: [1], hook: "h", emoji: "") }
    let trending = [InSeasonTrending(cityName: "City 1", searchCount: 1, emoji: ""), InSeasonTrending(cityName: "City 1", searchCount: 9, emoji: "")]
    let items = InSeason.items(picks: picks, trending: trending)
    #expect(items.count == InSeason.maxItems)
    #expect(Set(items.map(\.id)).count == items.count)
    #expect(items.first?.planned == 1)
  }

  @Test func loopDurationScalesButNeverDropsBelow30s() {
    #expect(InSeason.loopDuration(count: 2) == 30)
    #expect(InSeason.loopDuration(count: 12) == 72)
  }

  @Test func onlyMovesWithEnoughItemsToFillARow() {
    #expect(!InSeason.needsMarquee(count: 4))
    #expect(InSeason.needsMarquee(count: 5))
  }

  @Test func flagsAndMonths() {
    #expect(SeasonalPicks.flag(for: "PT") == "🇵🇹")
    #expect(SeasonalPicks.flag(for: "pt") == "🇵🇹")
    #expect(SeasonalPicks.flag(for: "").isEmpty)
    #expect(SeasonalPicks.flag(for: "P1").isEmpty)
    #expect(SeasonalPicks.picks(forMonth: 9).map(\.city).contains("Munich"))
    #expect(SeasonalPicks.picks(forMonth: 13).isEmpty)
  }
}
