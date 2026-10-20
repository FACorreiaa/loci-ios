import Foundation
import LociConnectProto
import Testing
import UserNotifications

@testable import loci

/// Taste match display and the "How was it?" queue (web: lib/taste/match.ts,
/// lib/ranking/flow.ts).
struct TasteMatchDisplayTests {
  private static func poi(score: Float?) -> Loci_Poi_POIDetailedInfo {
    var poi = Loci_Poi_POIDetailedInfo()
    if let score {
      var match = Loci_Poi_TasteMatch()
      match.score = score
      poi.tasteMatch = match
    }
    return poi
  }

  @Test func matchPercentRoundsAndHidesWhenUnset() {
    #expect(Self.poi(score: 0.874).matchPercent == 87)
    #expect(Self.poi(score: nil).matchPercent == nil)
    #expect(Self.poi(score: 0.874).matchLabel == "87% match")
  }

  @Test func cardChipThresholdIsSixty() {
    #expect(Self.poi(score: 0.6).showsMatchOnCard)
    #expect(!Self.poi(score: 0.59).showsMatchOnCard)
    #expect(!Self.poi(score: nil).showsMatchOnCard)
  }

  @Test func rateCategoryHasThreeActions() throws {
    let category = try #require(NotificationCategory.all.first { $0.identifier == NotificationCategory.lociRate })
    #expect(category.actions.map(\.identifier) == ["rate.loved", "rate.fine", "rate.notForMe"])
    #expect(category.actions.map(\.title) == ["Loved", "Fine", "Not for me"])
  }

  @Test func ratingCopyMatchesWeb() {
    #expect(HowWasItCopy.prompt("Sé") == "How was Sé?")
    #expect(HowWasItCopy.compare("Manteigaria") == "Better or worse than Manteigaria?")
    var place = Loci_Ranking_RankedPlace()
    place.rank = 2
    place.cityName = "Lisbon"
    #expect(HowWasItCopy.done(place) == "#2 in your Lisbon list")
  }
}
