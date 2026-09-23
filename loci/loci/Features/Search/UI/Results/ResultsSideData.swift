import Foundation
import LociConnectProto
import Observation

/// What a result page fetches beside the stream: the forecast and alerts,
/// exchange rates and the viewer's plan. Cached for the process so leaving and
/// re-opening a page does not refetch (web keeps them in query caches).
@Observable @MainActor final class ResultsSideData {
  private(set) var localContext: Loci_Localcontext_LocalContext?
  private(set) var fxRates: [Loci_Localcontext_FxRate] = []
  /// nil while unknown; web's `TripKit` treats unknown as free with a message.
  private(set) var plan: String?
  private(set) var planChecked = false
  private(set) var contextChecked = false

  private static var contextCache: [String: Loci_Localcontext_LocalContext] = [:]
  private static var fxCache: [String: [Loci_Localcontext_FxRate]] = [:]
  private static var cachedPlan: String?

  /// Offline pages (the design preview) never touch the network.
  static var isOffline: Bool { DesignPreview.requested != nil }

  var isPro: Bool { ProGate.isPro(plan: plan) }

  func loadContext(latitude: Double, longitude: Double) async {
    let key = String(format: "%.3f,%.3f", latitude, longitude)
    if let cached = Self.contextCache[key] {
      localContext = cached
      fxRates = Self.fxCache[key] ?? []
      contextChecked = true
      return
    }
    guard !Self.isOffline else { contextChecked = true; return }
    async let context = try? ResultsAPI.localContext(latitude: latitude, longitude: longitude)
    async let fx = try? ResultsAPI.fxRates(latitude: latitude, longitude: longitude)
    let (loadedContext, loadedFx) = await (context, fx)
    if let loadedContext {
      localContext = loadedContext
      Self.contextCache[key] = loadedContext
    }
    if let loadedFx {
      fxRates = loadedFx.rates
      Self.fxCache[key] = loadedFx.rates
    }
    contextChecked = true
  }

  func loadPlan() async {
    if let cached = Self.cachedPlan {
      plan = cached
      planChecked = true
      return
    }
    guard !Self.isOffline else { planChecked = true; return }
    if let loaded = try? await ResultsAPI.plan() {
      plan = loaded
      Self.cachedPlan = loaded
    }
    planChecked = true
  }

  /// A purchase or sign-out invalidates the cached plan.
  static func forgetPlan() { cachedPlan = nil }
}
