import LociConnectProto
import Testing

@testable import loci

@MainActor struct HereBriefModelTests {
  @Test func emptyUntilLoaded() {
    let model = HereBriefModel()
    #expect(model.placeName.isEmpty)
    #expect(!model.hasAnything)
  }

  @Test func placeNamePrefersLocalityThenRegion() {
    let model = HereBriefModel()
    var brief = Loci_Localcontext_HereBrief()
    brief.place.region = "Minho"
    model.brief = brief
    #expect(model.placeName == "Minho")
    brief.place.locality = "Viana do Castelo"
    model.brief = brief
    #expect(model.placeName == "Viana do Castelo")
  }

  @Test func weatherAloneCountsAsSomething() {
    let model = HereBriefModel()
    var brief = Loci_Localcontext_HereBrief()
    model.brief = brief
    #expect(!model.hasAnything)
    brief.weather = [Loci_Localcontext_WeatherDay()]
    model.brief = brief
    #expect(model.hasAnything)
  }
}
