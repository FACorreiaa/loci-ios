import Connect
import Foundation

/// A free-plan limit the server refused a write for (web: lib/entitlement-error.ts).
///
/// The server answers `PermissionDenied` with `x-loci-entitlement: lists | places`
/// (plus `-limit` and `-used`); older builds only say so in the message. The
/// copy is web's first sentence. Web's second ("Upgrade to Pro for …") is left
/// out: the iOS app does not point at a purchase outside the App Store
/// (guideline 3.1.1), so the sheet says how to make room instead.
nonisolated struct EntitlementLimit: LocalizedError, Equatable, Identifiable, Sendable {
  enum Feature: String, Sendable { case lists, places }

  let feature: Feature

  var id: String { feature.rawValue }

  static let header = "x-loci-entitlement"

  var title: String { "You've reached the free limit" }

  var message: String {
    switch feature {
    case .lists: "Free plans include 5 lists."
    case .places: "Free plans include 50 saved places."
    }
  }

  var errorDescription: String? { message }

  var suggestion: String {
    switch feature {
    case .lists: "Delete a list you no longer need to make room for a new one. Pro has no limit."
    case .places: "Remove a place from Saved or from a list to make room. Pro has no limit."
    }
  }

  /// Web's classifyEntitlementError. Only `PermissionDenied` counts; the header
  /// wins, then the message ("lists limit" / "places limit"), then web's
  /// catch-all for freemium wording, which it files under places.
  static func classify(code: Code?, headers: Headers, message: String?) -> EntitlementLimit? {
    guard code == .permissionDenied else { return nil }
    if let raw = headers.first(where: { $0.key.lowercased() == header })?.value.first,
      let feature = Feature(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased())
    {
      return EntitlementLimit(feature: feature)
    }
    let lower = (message ?? "").lowercased()
    if lower.contains("lists limit") || lower.contains("list limit") { return EntitlementLimit(feature: .lists) }
    if lower.contains("places limit") || lower.contains("place limit") { return EntitlementLimit(feature: .places) }
    if lower.range(of: "free plan|upgrade|entitlement|limit reached", options: .regularExpression) != nil {
      return EntitlementLimit(feature: .places)
    }
    return nil
  }

  static func classify(_ error: ConnectError?) -> EntitlementLimit? {
    guard let error else { return nil }
    return classify(code: error.code, headers: error.metadata, message: error.message)
  }
}
