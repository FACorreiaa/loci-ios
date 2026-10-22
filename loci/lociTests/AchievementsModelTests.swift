import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing
import UIKit

@testable import loci

struct AchievementsModelTests {
  private func achievement(kind: Loci_Achievement_AchievementKind, tier: Loci_Achievement_AchievementTier = .unspecified)
    -> Loci_Achievement_Achievement
  {
    var a = Loci_Achievement_Achievement()
    a.id = "\(kind.rawValue)-\(tier.rawValue)"
    a.title = "Cartographer"
    a.kind = kind
    a.tier = tier
    return a
  }

  @Test(arguments: [
    (0, AchievementTier.unranked),
    (1, .bronze),
    (2, .silver),
    (3, .gold),
    (4, .platinum),
  ])
  func tierFollowsTheProtoNumbers(_ raw: Int, _ expected: AchievementTier) throws {
    let proto = try #require(Loci_Achievement_AchievementTier(rawValue: raw))
    #expect(AchievementTier(proto) == expected)
  }

  @Test func onlyATrackRungNamesItsTier() {
    #expect(achievement(kind: .track, tier: .gold).label == "Cartographer · Gold")
    #expect(achievement(kind: .track).label == "Cartographer")
    #expect(achievement(kind: .moment, tier: .gold).label == "Cartographer")
  }

  @Test func rarityHidesUntilKnownAndFloorsAtOnePercent() {
    #expect(AchievementText.rarity(nil) == nil)
    #expect(AchievementText.rarity(0.4) == "Held by under 1% of explorers")
    #expect(AchievementText.rarity(12.6) == "Held by 13% of explorers")
    var a = achievement(kind: .moment)
    #expect(a.rarityLine == nil)
    a.rarityPct = 0
    #expect(a.rarityLine == "Held by under 1% of explorers")
  }

  @Test func progressShareIsClampedAndFullWhenNothingIsLeft() {
    var a = achievement(kind: .track)
    a.progress = 17
    a.nextTarget = 30
    #expect(abs(a.progressShare - 17.0 / 30.0) < 0.0001)
    a.progress = 40
    #expect(a.progressShare == 1)
    a.nextTarget = 0
    #expect(a.progressShare == 1)
  }

  @Test func theBestUnlockIsASecretThenTheHighestTier() {
    let moment = achievement(kind: .moment)
    let silver = achievement(kind: .track, tier: .silver)
    let gold = achievement(kind: .track, tier: .gold)
    let secret = achievement(kind: .secret)
    #expect([moment, silver, gold].best?.id == gold.id)
    #expect([gold, secret, moment].best?.id == secret.id)
    #expect([moment].best?.id == moment.id)
    #expect([Loci_Achievement_Achievement]().best == nil)
  }

  @Test func everyIconKeyIsARealSymbolAndUnknownKeysFallBack() {
    for (key, symbol) in AchievementText.symbols {
      #expect(UIImage(systemName: symbol) != nil, "\(key) → \(symbol)")
    }
    #expect(UIImage(systemName: AchievementText.fallbackSymbol) != nil)
    #expect(AchievementText.symbol("not-a-key") == AchievementText.fallbackSymbol)
  }

  @MainActor @Test func storeFiltersGroupsAndRevealsOnce() async {
    let store = AchievementsStore(service: PreviewAchievementsService())
    await store.load()
    #expect(store.phase == .loaded)
    #expect(store.total == 79)
    #expect(store.showsReveal)
    #expect(store.groups.map(\.kind) == [.track, .moment, .secret])

    store.filter = .earned
    let allEarned = store.shown.allSatisfy { $0.isEarned }
    #expect(allEarned)
    store.filter = .next
    let closeness = store.shown.map(\.closeness)
    #expect(closeness == closeness.sorted(by: >))
    let anyHidden = store.shown.contains { $0.hidden }
    #expect(!anyHidden)

    await store.dismissReveal()
    #expect(!store.showsReveal)
    #expect(store.fresh.isEmpty)
  }

  @MainActor @Test func someoneElsesAchievementsNeverReveal() async {
    let store = AchievementsStore(userID: "u-ana", service: PreviewAchievementsService())
    await store.load()
    #expect(!store.isOwn)
    #expect(!store.showsReveal)
  }

  @Test func weekStreakLineAsksForThisWeekUntilItCounts() {
    var streak = Loci_Gamification_WeekStreak()
    #expect(streak.line == "Explore this week to start a streak")
    streak.current = 3
    #expect(streak.line == "3 weeks in a row · explore this week to keep it")
    streak.exploredThisWeek = true
    #expect(streak.line == "3 weeks in a row")
  }

  @Test func streakReminderLandsOnTheSundayThatMatters() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Lisbon"))
    // Wednesday 2026-10-21 10:00.
    let wednesday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 10)))
    var streak = Loci_Gamification_WeekStreak()
    #expect(StreakReminder.fireDate(after: streak, now: wednesday, calendar: calendar) == nil)

    streak.current = 2
    let thisSunday = try #require(StreakReminder.fireDate(after: streak, now: wednesday, calendar: calendar))
    #expect(calendar.dateComponents([.month, .day, .hour], from: thisSunday) == DateComponents(month: 10, day: 25, hour: 18))

    streak.exploredThisWeek = true
    let nextSunday = try #require(StreakReminder.fireDate(after: streak, now: wednesday, calendar: calendar))
    #expect(calendar.dateComponents([.month, .day, .hour], from: nextSunday) == DateComponents(month: 11, day: 1, hour: 18))

    // Sunday after the hour: this week's reminder has passed; next week's is the one.
    let lateSunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 20)))
    let after = try #require(StreakReminder.fireDate(after: streak, now: lateSunday, calendar: calendar))
    #expect(calendar.dateComponents([.month, .day], from: after) == DateComponents(month: 11, day: 1))
  }
}
