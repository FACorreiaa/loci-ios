import Foundation
import LociConnectProto
import Testing

@testable import loci

/// Pass 3, Phase 3: the "should I go?" verdict on the here-brief (web:
/// GoScoreCard) and the fuel line on a multi-city trip (web: TripMoney).
struct GoScoreModelTests {
  private func score(_ verdict: String, _ value: Int32 = 72, estimated: Bool = false) -> Loci_Localcontext_GoScore {
    var s = Loci_Localcontext_GoScore()
    s.score = value
    s.verdict = verdict
    s.summary = "Dry and mild, light crowds."
    s.hasEstimatedInputs_p = estimated
    return s
  }

  private func factor(_ label: String, _ contribution: Int32, _ max: Int32, detail: String = "") -> Loci_Localcontext_ScoreFactor {
    var f = Loci_Localcontext_ScoreFactor()
    f.label = label
    f.contribution = contribution
    f.maxContribution = max
    f.detail = detail
    return f
  }

  @Test func verdictsMapToWebsTonesAndWords() {
    #expect(GoScoreModel(score("go")).tone == .go)
    #expect(GoScoreModel(score("go")).label == "Worth going")
    #expect(GoScoreModel(score("skip")).tone == .skip)
    #expect(GoScoreModel(score("skip")).label == "Probably skip")
    #expect(GoScoreModel(score("maybe")).tone == .maybe)
    #expect(GoScoreModel(score("maybe")).label == "Could work")
    #expect(GoScoreModel(score("")).tone == .maybe, "an empty verdict reads as maybe, as on web")
    #expect(GoScoreModel(score("GO")).tone == .go)
  }

  @Test func factorRowsCarryAClampedShareAndWebsNumberWording() {
    var s = score("go")
    s.factors = [factor("Weather", 30, 40, detail: "18° and dry"), factor("Crowds", -10, 0), factor("Distance", 50, 40)]
    let rows = GoScoreModel(s).factorRows
    #expect(rows.map(\.label) == ["Weather", "Crowds", "Distance"])
    #expect(rows[0].share == 0.75)
    #expect(rows[0].valueText == "30 / 40")
    #expect(rows[0].detail == "18° and dry")
    #expect(rows[1].share == nil, "no bar without a maximum")
    #expect(rows[1].valueText == "-10")
    #expect(rows[1].isNegative)
    #expect(rows[2].share == 1, "over the maximum clamps to a full bar")
  }

  @Test func estimatedInputsNoteOnlyWhenTheServerSaysSo() {
    #expect(GoScoreModel(score("go")).estimatedNote == nil)
    #expect(GoScoreModel(score("go", estimated: true)).estimatedNote?.hasPrefix("Some inputs are estimated") == true)
  }

  @Test func driveCostWordingMatchesWeb() {
    var e = Loci_Localcontext_DriveCostEstimate()
    e.distanceKm = 119.6
    e.litres = 8.37
    e.cost = 14.238
    e.currency = "EUR"
    e.assumptions = "7 L/100 km at 1.70 EUR/L"
    let model = DriveCostModel(e, locale: Locale(identifier: "en_US"))
    #expect(model.line == "Fuel ≈ 14.24 EUR")
    #expect(model.detail == "120 km · 8.4 L")
    #expect(model.assumptions == "7 L/100 km at 1.70 EUR/L")
  }

  @Test func driveKmIsTheSumOfEveryLeg() {
    var a = Loci_Trip_TripLeg()
    a.distanceKm = 120
    var b = Loci_Trip_TripLeg()
    b.distanceKm = 35.5
    #expect(DriveCostModel.totalKm([a, b]) == 155.5)
    #expect(DriveCostModel.totalKm([]) == 0)
  }
}
