import Foundation
import Testing

@testable import loci

@MainActor
struct PendingInviteTests {
  private func freshDefaults() throws -> UserDefaults {
    let name = "PendingInviteTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  @Test func keepsTheCodeUntilCleared() throws {
    let defaults = try freshDefaults()
    PendingInvite.remember("Ab-_12cd34EF", defaults: defaults)
    #expect(PendingInvite.code(defaults: defaults) == "Ab-_12cd34EF")
    PendingInvite.clear(defaults: defaults)
    #expect(PendingInvite.code(defaults: defaults) == nil)
  }

  @Test func goesStaleAfterThirtyDays() throws {
    let defaults = try freshDefaults()
    let then = Date(timeIntervalSince1970: 1_800_000_000)
    PendingInvite.remember("Ab-_12cd34EF", defaults: defaults, now: then)
    #expect(PendingInvite.code(defaults: defaults, now: then.addingTimeInterval(29 * 86_400)) == "Ab-_12cd34EF")
    #expect(PendingInvite.code(defaults: defaults, now: then.addingTimeInterval(31 * 86_400)) == nil)
    #expect(defaults.string(forKey: "pendingInvite.code") == nil, "a stale code is removed")
  }

  @Test func ignoresEmptyAndOversizedCodes() throws {
    let defaults = try freshDefaults()
    PendingInvite.remember("", defaults: defaults)
    PendingInvite.remember(String(repeating: "x", count: PendingInvite.maxCodeLength + 1), defaults: defaults)
    #expect(PendingInvite.code(defaults: defaults) == nil)
  }
}
