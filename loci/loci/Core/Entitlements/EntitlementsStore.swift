import Foundation
import LociConnectProto
import Observation

/// The signed-in account's plan, refreshed on sign-in and after a free-limit
/// refusal, with the last known copy shown on a cold launch (`cacheThrough`).
/// Nothing reads it to gate a feature while `PlanGating.enabled` is false;
/// the You hub shows it, and the results pages use the same plan names.
@MainActor @Observable final class EntitlementsStore {
  static let shared = EntitlementsStore()

  private(set) var current: Entitlements = .free
  /// How `current` was obtained; nil until the first refresh for a user.
  private(set) var loaded: Loaded<Loci_Entitlement_V1_Entitlements>?
  private(set) var userID: String?

  private let cache: LocalCache
  private let fetch: @Sendable () async throws -> Loci_Entitlement_V1_Entitlements

  init(cache: LocalCache = .shared, fetch: @escaping @Sendable () async throws -> Loci_Entitlement_V1_Entitlements = EntitlementsAPI.fetchProto) {
    self.cache = cache
    self.fetch = fetch
  }

  /// Copy first, then the server. Without a user there is nothing to ask for.
  func refresh(userID: String?) async {
    guard let userID, !userID.isEmpty else {
      reset()
      return
    }
    if self.userID != userID {
      self.userID = userID
      current = .free
      loaded = nil
    }
    let fetch = fetch
    let result = await cacheThrough(
      Loci_Entitlement_V1_Entitlements.self,
      kind: .entitlements,
      id: userID,
      cache: cache,
      onCached: { [weak self] copy in
        // A sign-out or account switch while this was loading wins.
        guard let self, self.userID == userID else { return }
        self.current = Entitlements(copy.value)
      }
    ) { try await fetch() }
    guard self.userID == userID else { return }
    loaded = result
    if let value = result.value { current = Entitlements(value) }
  }

  /// After a free-limit refusal the counters are stale: ask again.
  func invalidate() async {
    await refresh(userID: userID ?? AuthSessionManager.shared.currentUserID)
  }

  /// Sign-out: back to the free shape, no user.
  func reset() {
    userID = nil
    current = .free
    loaded = nil
  }
}
