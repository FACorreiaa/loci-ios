import Foundation
import SwiftProtobuf

/// What a cache-through load produced: the server's answer, the phone's copy
/// because the server could not be reached, or nothing.
nonisolated enum Loaded<M: Sendable>: Sendable {
  case fresh(M)
  case stale(M, since: Date, reason: APIError)
  case missing(APIError)

  var value: M? {
    switch self {
    case .fresh(let value), .stale(let value, _, _): value
    case .missing: nil
    }
  }

  var staleSince: Date? {
    if case .stale(_, let since, _) = self { return since }
    return nil
  }

  /// True only for a network failure: the "Offline" wording, as opposed to
  /// a server error while connected, which keeps the "Saved" wording.
  var isOffline: Bool {
    if case .stale(_, _, .network) = self { return true }
    if case .missing(.network) = self { return true }
    return false
  }
}

/// Render the copy first (`onCached`), then fetch. Success overwrites the
/// copy; a failure keeps it. `APIError.network` is the only "offline" reason;
/// any other failure with a copy still shows the copy so an expired token
/// does not blank a page the phone could draw.
nonisolated func cacheThrough<M: SwiftProtobuf.Message & Sendable>(
  _ type: M.Type,
  kind: LocalCache.Kind,
  id: String,
  cache: LocalCache = .shared,
  onCached: (@MainActor (Cached<M>) -> Void)? = nil,
  fetch: () async throws -> M
) async -> Loaded<M> {
  let copy = await cache.get(type, kind: kind, id: id)
  if let copy, let onCached { await onCached(copy) }
  do {
    let value = try await fetch()
    try? await cache.put(value, kind: kind, id: id)
    return .fresh(value)
  } catch {
    let reason = (error as? APIError) ?? .custom(error.localizedDescription)
    if let copy { return .stale(copy.value, since: copy.fetchedAt, reason: reason) }
    return .missing(reason)
  }
}
