import LociConnectProto
import SwiftUI

/// `-designPreview goScoreGood | goScoreMaybe | driveCost`.
enum GoScorePreview {
  static func card(verdict: String, score: Int32, estimated: Bool = false) -> some View {
    var s = Loci_Localcontext_GoScore()
    s.score = score
    s.verdict = verdict
    s.summary = verdict == "go" ? "Dry and mild, light crowds, an easy drive." : "Showers likely on Saturday; Sunday clears."
    s.hasEstimatedInputs_p = estimated
    s.factors = [
      factor("Weather", verdict == "go" ? 34 : 14, 40, "18° and dry"),
      factor("Crowds", 18, 25, "Off-season"),
      factor("Distance", verdict == "go" ? 29 : 22, 35, "1h 40 by car"),
    ]
    return GoScoreCard(model: GoScoreModel(s), cityName: "Évora").padding()
  }

  static func driveCost() -> some View {
    var e = Loci_Localcontext_DriveCostEstimate()
    e.distanceKm = 274
    e.litres = 19.2
    e.cost = 32.64
    e.currency = "EUR"
    e.assumptions = "7 L/100 km at 1.70 EUR/L; tolls not included"
    return List { Section("Travel between cities") { DriveCostRow(model: DriveCostModel(e)) } }
  }

  private static func factor(_ label: String, _ contribution: Int32, _ max: Int32, _ detail: String) -> Loci_Localcontext_ScoreFactor {
    var f = Loci_Localcontext_ScoreFactor()
    f.label = label
    f.contribution = contribution
    f.maxContribution = max
    f.detail = detail
    return f
  }
}
