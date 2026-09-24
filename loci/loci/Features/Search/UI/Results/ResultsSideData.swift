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
  /// How the forecast was obtained, for the cache chip.
  private(set) var contextLoaded: Loaded<Loci_Localcontext_LocalContext>?

  private static var cachedPlan: String?

  /// Offline pages (the design preview) never touch the network.
  static var isOffline: Bool { DesignPreview.requested != nil }

  var isPro: Bool { ProGate.isPro(plan: plan) }

  /// The phone's copy of the forecast and rates first, then the server.
  func loadContext(latitude: Double, longitude: Double) async {
    guard !Self.isOffline else { contextChecked = true; return }
    let key = LocalCache.key(latitude: latitude, longitude: longitude)
    async let context = cacheThrough(Loci_Localcontext_LocalContext.self, kind: .localContext, id: key, onCached: { self.localContext = $0.value }) {
      try await ResultsAPI.localContext(latitude: latitude, longitude: longitude)
    }
    async let fx = cacheThrough(Loci_Localcontext_GetFxRatesResponse.self, kind: .fx, id: key, onCached: { self.fxRates = $0.value.rates }) {
      try await ResultsAPI.fxRates(latitude: latitude, longitude: longitude)
    }
    let (loadedContext, loadedFx) = await (context, fx)
    if let value = loadedContext.value { localContext = value }
    if let value = loadedFx.value { fxRates = value.rates }
    contextLoaded = loadedContext
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
