import Foundation
import LociConnectProto

/// The account's plan and free-tier counters (web: lib/api/entitlements.ts).
/// Read-only: nothing is gated by it while `PlanGating.enabled` is false, and
/// the app never points at a purchase. `-1` on a limit means unlimited.
nonisolated struct Entitlements: Equatable, Sendable {
  var plan: String
  var listsUsed: Int
  var listsLimit: Int
  var placesSaved: Int
  var placesLimit: Int
  var advancedFilters: Bool
  var exportFull: Bool

  /// What the server hands a free account (5 lists, 50 saved places).
  static let free = Entitlements(
    plan: "free", listsUsed: 0, listsLimit: 5, placesSaved: 0, placesLimit: 50, advancedFilters: false, exportFull: false
  )

  init(plan: String, listsUsed: Int, listsLimit: Int, placesSaved: Int, placesLimit: Int, advancedFilters: Bool, exportFull: Bool) {
    self.plan = plan
    self.listsUsed = listsUsed
    self.listsLimit = listsLimit
    self.placesSaved = placesSaved
    self.placesLimit = placesLimit
    self.advancedFilters = advancedFilters
    self.exportFull = exportFull
  }

  init(_ proto: Loci_Entitlement_V1_Entitlements) {
    self.init(
      plan: proto.plan,
      listsUsed: Int(proto.listsUsed),
      listsLimit: Int(proto.listsLimit),
      placesSaved: Int(proto.placesSaved),
      placesLimit: Int(proto.placesLimit),
      advancedFilters: proto.advancedFilters,
      exportFull: proto.exportFull
    )
  }

  /// The same plan names the results pages treat as Pro (`ProGate.proPlans`).
  var isPro: Bool { ProGate.isPro(plan: plan) }

  /// Nil when unlimited; never below zero.
  var listsRemaining: Int? { Self.remaining(used: listsUsed, limit: listsLimit) }
  var placesRemaining: Int? { Self.remaining(used: placesSaved, limit: placesLimit) }

  /// "Pro", or "Free · 3/5 lists · 12/50 places" with only the limited counters.
  var chipText: String {
    if isPro { return "Pro" }
    var parts = [plan.isEmpty ? "Free" : plan.prefix(1).uppercased() + plan.dropFirst()]
    if listsLimit >= 0 { parts.append("\(listsUsed)/\(listsLimit) lists") }
    if placesLimit >= 0 { parts.append("\(placesSaved)/\(placesLimit) places") }
    return parts.joined(separator: " · ")
  }

  private static func remaining(used: Int, limit: Int) -> Int? {
    limit < 0 ? nil : max(0, limit - used)
  }
}

extension Entitlements {
  static let previewPro = Entitlements(
    plan: "pro", listsUsed: 9, listsLimit: -1, placesSaved: 140, placesLimit: -1, advancedFilters: true, exportFull: true
  )
  static let previewFree = Entitlements(
    plan: "free", listsUsed: 3, listsLimit: 5, placesSaved: 12, placesLimit: 50, advancedFilters: false, exportFull: false
  )
}
