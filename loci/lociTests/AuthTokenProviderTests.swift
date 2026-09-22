import Foundation
import Testing

@testable import loci

/// In-memory stand-in for the Keychain.
final class MemoryStore: SecureStringStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: String]

  init(_ values: [String: String] = [:]) { self.values = values }
  func string(for key: String) throws -> String? { lock.withLock { values[key] } }
  func setString(_ value: String, for key: String) throws { lock.withLock { values[key] = value } }
  func removeValue(for key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}

/// Counts calls across tasks.
actor Counter {
  private(set) var value = 0

  func increment() { value += 1 }
}

/// An unsigned JWT whose payload carries only `exp`.
func jwt(expiringAt date: Date) -> String {
  let payload = #"{"exp":\#(Int(date.timeIntervalSince1970))}"#
  let encoded = Data(payload.utf8).base64EncodedString()
    .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  return "eyJhbGciOiJub25lIn0.\(encoded)."
}

struct AuthTokenProviderTests {
  @Test func returnsStoredTokenWithoutRefreshingWhileValid() async {
    let valid = jwt(expiringAt: Date().addingTimeInterval(3600))
    let calls = Counter()
    let provider = AuthTokenProvider(
      store: MemoryStore([AuthKeychainKeys.accessToken: valid, AuthKeychainKeys.refreshToken: "r"]),
      performRefresh: { _ in
        await calls.increment()
        return .unavailable
      },
      onSessionEnded: {}
    )
    #expect(await provider.accessToken() == valid)
    #expect(await calls.value == 0)
  }

  @Test func concurrentCallersShareOneRefresh() async throws {
    let expired = jwt(expiringAt: Date().addingTimeInterval(-60))
    let store = MemoryStore([AuthKeychainKeys.accessToken: expired, AuthKeychainKeys.refreshToken: "r1"])
    let calls = Counter()
    let provider = AuthTokenProvider(
      store: store,
      performRefresh: { _ in
        await calls.increment()
        try? await Task.sleep(for: .milliseconds(50))
        return .refreshed(accessToken: "new-access", refreshToken: "r2")
      },
      onSessionEnded: {}
    )

    let tokens = await withTaskGroup(of: String?.self) { group in
      for _ in 0..<8 { group.addTask { await provider.accessToken() } }
      return await group.reduce(into: []) { $0.append($1) }
    }

    #expect(tokens.allSatisfy { $0 == "new-access" })
    #expect(await calls.value == 1)
    #expect(try store.string(for: AuthKeychainKeys.refreshToken) == "r2")
  }

  @Test func rejectedRefreshEndsTheSession() async {
    let ended = Counter()
    let provider = AuthTokenProvider(
      store: MemoryStore([AuthKeychainKeys.accessToken: jwt(expiringAt: .distantPast), AuthKeychainKeys.refreshToken: "r"]),
      performRefresh: { _ in .rejected },
      onSessionEnded: { await ended.increment() }
    )
    #expect(await provider.accessToken() == nil)
    #expect(await ended.value == 1)
  }

  @Test func unreachableServerKeepsTheSession() async throws {
    let ended = Counter()
    let store = MemoryStore([AuthKeychainKeys.accessToken: jwt(expiringAt: .distantPast), AuthKeychainKeys.refreshToken: "r"])
    let provider = AuthTokenProvider(store: store, performRefresh: { _ in .unavailable }, onSessionEnded: { await ended.increment() })
    #expect(await provider.accessToken() == nil)
    #expect(await ended.value == 0)
    #expect(try store.string(for: AuthKeychainKeys.refreshToken) == "r")
  }
}
