import Foundation
import LociConnectProto
import Testing
import UserNotifications

@testable import loci

/// The standing-task push (loci-connect-server docs/push.md, "Standing tasks")
/// and the search-finished push, as the app routes them.
struct ChatPushTests {
  /// The server's payload for a standing task's message, verbatim.
  static func standingTask(sessionId: String = "3f0c9a1e-7b1d-4c8a-9d52-1a2b3c4d5e6f", messageId: String? = "9a8b7c6d-0000-4000-8000-000000000001")
    -> [AnyHashable: Any]
  {
    var payload: [AnyHashable: Any] = [
      "aps": [
        "alert": ["title": "Rain in Lisbon", "body": "Rain from 14:00, take a jacket."],
        "sound": "default",
        "thread-id": "session-\(sessionId)",
        "category": "loci_chat",
      ] as [String: Any],
      "sessionId": sessionId,
      "cityName": "Lisbon",
      "domain": "itinerary",
      "url": "https://lociai.fyi/itinerary?sessionId=\(sessionId)&cityName=Lisbon&domain=itinerary",
      "origin": "proactive",
      "sourceLabel": "Standing task",
    ]
    if let messageId { payload["messageId"] = messageId }
    return payload
  }

  /// The search-finished push: thread-id "search", no category.
  static func searchFinished(sessionId: String = "s1") -> [AnyHashable: Any] {
    [
      "aps": [
        "alert": ["title": "Your itinerary for Porto is ready", "body": "Tap to see it."], "sound": "default", "thread-id": "search",
      ] as [String: Any],
      "sessionId": sessionId,
      "cityName": "Porto",
      "domain": "itinerary",
      "status": "completed",
      "url": "https://lociai.fyi/itinerary?sessionId=\(sessionId)&cityName=Porto&domain=itinerary",
    ]
  }

  // MARK: - Parsing

  @Test func parsesTheServerPayload() throws {
    let push = try #require(ChatPush(userInfo: Self.standingTask()))
    #expect(
      push.link == SessionLink(destination: .itinerary, sessionId: "3f0c9a1e-7b1d-4c8a-9d52-1a2b3c4d5e6f", cityName: "Lisbon", domain: "itinerary")
    )
    #expect(push.messageId == "9a8b7c6d-0000-4000-8000-000000000001")
    #expect(push.sourceLabel == "Standing task")
    #expect(push.refresh == ThreadRefresh(sessionId: push.link.sessionId, messageId: push.messageId))
  }

  @Test func missingMessageIdStillOpensTheThread() throws {
    let push = try #require(ChatPush(userInfo: Self.standingTask(messageId: nil)))
    #expect(push.messageId == nil)
    var blank = Self.standingTask()
    blank["messageId"] = "  "
    #expect(ChatPush(userInfo: blank)?.messageId == nil)
    var wrongType = Self.standingTask()
    wrongType["messageId"] = 42
    #expect(ChatPush(userInfo: wrongType)?.messageId == nil)
  }

  @Test func emptyCityAndMissingDomainOpenAnItinerary() throws {
    var payload = Self.standingTask()
    payload["cityName"] = ""
    payload["domain"] = nil
    let push = try #require(ChatPush(userInfo: payload))
    #expect(push.link.cityName == nil)
    #expect(push.link.destination == .itinerary)
  }

  @Test func unknownKeysAreIgnored() {
    var payload = Self.standingTask()
    payload["watchId"] = "w-1"
    payload["schemaVersion"] = 2
    payload["aps"] = ["category": "loci_chat", "mutable-content": 1, "interruption-level": "active"] as [String: Any]
    #expect(ChatPush(userInfo: payload) != nil)
  }

  @Test func needsASession() {
    var payload = Self.standingTask()
    payload["sessionId"] = nil
    #expect(ChatPush(userInfo: payload) == nil)
    payload["sessionId"] = ""
    #expect(ChatPush(userInfo: payload) == nil)
  }

  @Test func theCategoryOrTheOriginMarksAChatPush() {
    var categoryOnly = Self.standingTask()
    categoryOnly["origin"] = nil
    #expect(ChatPush(userInfo: categoryOnly) != nil)

    var originOnly = Self.standingTask()
    originOnly["aps"] = ["alert": "x"] as [String: Any]
    #expect(ChatPush(userInfo: originOnly) != nil)
  }

  @Test func theSearchFinishedPushIsNotAChatPush() {
    #expect(ChatPush(userInfo: Self.searchFinished()) == nil)
    #expect(ChatPush(userInfo: SessionLink(destination: .hotels, sessionId: "s", cityName: "Rome", domain: "accommodation").userInfo) == nil)
    var otherCategory = Self.searchFinished()
    otherCategory["aps"] = ["category": "something_else"] as [String: Any]
    #expect(ChatPush(userInfo: otherCategory) == nil)
  }

  // MARK: - Category

  @Test func registersTheChatCategoryWithoutActions() throws {
    let category = try #require(NotificationCategory.all.first { $0.identifier == "loci_chat" })
    #expect(category.actions.isEmpty)
    #expect(NotificationCategory.lociChat == "loci_chat")
  }

  /// The test host launched through AppDelegate, which configured the center.
  @MainActor @Test func theCenterHasTheCategoryAfterLaunch() async {
    PushNotificationManager.shared.configure()
    let registered = await UNUserNotificationCenter.current().notificationCategories()
    #expect(registered.contains { $0.identifier == NotificationCategory.lociChat })
  }

  // MARK: - Tap

  @Test func tappingAChatPushOpensTheThreadAtTheMessage() throws {
    let push = try #require(ChatPush(userInfo: Self.standingTask()))
    #expect(PushRoute.tap(userInfo: Self.standingTask()) == .openThread(push.link, push.refresh))
  }

  @Test func tappingTheSearchPushStillJustOpensTheSession() {
    let link = SessionLink(destination: .itinerary, sessionId: "s1", cityName: "Porto", domain: "itinerary")
    #expect(PushRoute.tap(userInfo: Self.searchFinished()) == .open(link))
  }

  @Test func tappingSomethingElseDoesNothing() {
    #expect(PushRoute.tap(userInfo: ["poi": "Sé"]) == .nothing)
    #expect(PushRoute.tap(userInfo: [:]) == .nothing)
  }

  // MARK: - Foreground

  @Test func chatPushForThePageOnScreenRefreshesItQuietly() {
    let payload = Self.standingTask(sessionId: "s9")
    #expect(
      PushRoute.presentation(userInfo: payload, viewingSessionId: "s9")
        == .suppressAndRefresh(ThreadRefresh(sessionId: "s9", messageId: "9a8b7c6d-0000-4000-8000-000000000001"))
    )
  }

  @Test func chatPushForAnotherSessionShowsTheBanner() {
    let payload = Self.standingTask(sessionId: "s9")
    #expect(PushRoute.presentation(userInfo: payload, viewingSessionId: "other") == .banner)
    #expect(PushRoute.presentation(userInfo: payload, viewingSessionId: nil) == .banner)
  }

  @Test func searchPushKeepsItsRule() {
    #expect(PushRoute.presentation(userInfo: Self.searchFinished(sessionId: "s1"), viewingSessionId: "s1") == .suppress)
    #expect(PushRoute.presentation(userInfo: Self.searchFinished(sessionId: "s1"), viewingSessionId: "s2") == .banner)
    #expect(PushRoute.presentation(userInfo: Self.searchFinished(sessionId: "s1"), viewingSessionId: nil) == .banner)
    #expect(PushRoute.presentation(userInfo: ["poi": "Sé"], viewingSessionId: "s1") == .banner)
  }
}

@MainActor struct ThreadRefreshRoutingTests {
  @Test func openingFromAChatPushLeavesARefreshForThatPage() {
    let router = AppRouter()
    let link = SessionLink(destination: .itinerary, sessionId: "s1", domain: "itinerary")
    router.open(link, refresh: ThreadRefresh(sessionId: "s1", messageId: "m1"))
    #expect(router.selectedTab == .assistant)
    #expect(router.pendingSession == link)
    #expect(router.takeThreadRefresh(for: "other") == nil)
    #expect(router.takeThreadRefresh(for: "s1") == ThreadRefresh(sessionId: "s1", messageId: "m1"))
    // Taken once.
    #expect(router.takeThreadRefresh(for: "s1") == nil)
  }

  @Test func aForegroundRefreshDoesNotNavigate() {
    let router = AppRouter()
    router.refreshThread(ThreadRefresh(sessionId: "s1", messageId: nil))
    #expect(router.pendingSession == nil)
    #expect(router.selectedTab == .discover)
    #expect(router.threadRefresh == ThreadRefresh(sessionId: "s1", messageId: nil))
  }
}
