import Foundation
import LociConnectProto

/// The "should I go?" verdict as the card draws it (web: GoScoreCard). The
/// factors render by default so the traveller can overrule the number.
nonisolated struct GoScoreModel: Equatable, Sendable {
  enum Tone: Sendable { case go, maybe, skip }

  struct FactorRow: Identifiable, Equatable, Sendable {
    let id: Int
    let label: String
    let contribution: Int
    let maxContribution: Int
    let detail: String

    /// 0…1 of the bar; nil when the factor has no maximum to measure against.
    var share: Double? {
      guard maxContribution > 0 else { return nil }
      return min(1, max(0, Double(contribution) / Double(maxContribution)))
    }

    var isNegative: Bool { contribution < 0 }

    /// "30 / 40", or just "-10" when there is no maximum.
    var valueText: String { maxContribution > 0 ? "\(contribution) / \(maxContribution)" : "\(contribution)" }
  }

  let score: Int
  let verdict: String
  let summary: String
  let factorRows: [FactorRow]
  let hasEstimatedInputs: Bool

  init(_ proto: Loci_Localcontext_GoScore) {
    score = Int(proto.score)
    verdict = proto.verdict.lowercased()
    summary = proto.summary
    factorRows = proto.factors.enumerated().map { index, f in
      FactorRow(id: index, label: f.label, contribution: Int(f.contribution), maxContribution: Int(f.maxContribution), detail: f.detail)
    }
    hasEstimatedInputs = proto.hasEstimatedInputs_p
  }

  var tone: Tone {
    switch verdict {
    case "go": .go
    case "skip": .skip
    default: .maybe
    }
  }

  var label: String {
    switch tone {
    case .go: "Worth going"
    case .skip: "Probably skip"
    case .maybe: "Could work"
    }
  }

  /// web's note under the card; nil when every input was live.
  var estimatedNote: String? {
    hasEstimatedInputs ? "Some inputs are estimated — no live weather source, so treat the forecast part as a guess." : nil
  }
}

/// The fuel line on a trip with legs (web: TripMoney). Always shown with its
/// assumptions: a bare figure about someone's money invites either misplaced
/// trust or dismissal, and only the assumptions let them correct it.
nonisolated struct DriveCostModel: Equatable, Sendable {
  let distanceKm: Double
  let litres: Double
  let cost: Double
  let currency: String
  let assumptions: String
  let locale: Locale

  init(_ proto: Loci_Localcontext_DriveCostEstimate, locale: Locale = .current) {
    distanceKm = proto.distanceKm
    litres = proto.litres
    cost = proto.cost
    currency = proto.currency
    assumptions = proto.assumptions
    self.locale = locale
  }

  /// "Fuel ≈ 14.24 EUR"
  var line: String { "Fuel ≈ \(cost.formatted(.number.precision(.fractionLength(2)).locale(locale))) \(currency)" }

  /// "120 km · 8.4 L"
  var detail: String {
    "\(Int(distanceKm.rounded())) km · \(litres.formatted(.number.precision(.fractionLength(1)).locale(locale))) L"
  }

  /// web: totalDriveKm — every leg counts; zero hides the line.
  static func totalKm(_ legs: [Loci_Trip_TripLeg]) -> Double { legs.reduce(0) { $0 + $1.distanceKm } }
}
