import Foundation
import UserNotifications

/// Notification categories the app registers at launch. The server names one
/// in `aps.category`; a category with no actions still has to be registered for
/// iOS to treat the push as that category.
nonisolated enum NotificationCategory {
  /// A message the agent posted into a chat thread on its own (a standing task
  /// running). loci-connect-server `push.ProactiveCategory`.
  static let lociChat = "loci_chat"

  /// Everything registered with `setNotificationCategories`. The search-finished
  /// push and the local notifications carry no category and need none.
  static var all: Set<UNNotificationCategory> {
    [UNNotificationCategory(identifier: lociChat, actions: [], intentIdentifiers: [], options: [])]
  }
}

/// A push saying the agent posted into a thread: loci-connect-server
/// docs/push.md, "Standing tasks (proactive messages)". Routed like any other
/// session push (`SessionLink(userInfo:)`); on top of that the thread's stored
/// messages are fetched again so the new one is on the page, and the page
/// scrolls to `messageId` when the server named it.
nonisolated struct ChatPush: Sendable, Equatable {
  enum Key {
    static let aps = "aps"
    static let category = "category"
    static let messageId = "messageId"
    static let origin = "origin"
    static let sourceLabel = "sourceLabel"
  }

  var link: SessionLink
  var messageId: String?
  var sourceLabel: String?

  /// Nil for anything that is not a chat push, including the search-finished
  /// push (thread-id "search", no category) and payloads without a session.
  /// Keys this build does not know are ignored.
  init?(userInfo: [AnyHashable: Any]) {
    let aps = userInfo[Key.aps] as? [AnyHashable: Any]
    let category = aps?[Key.category] as? String
    let origin = userInfo[Key.origin] as? String
    guard category == NotificationCategory.lociChat || origin == "proactive" else { return nil }
    guard let link = SessionLink(userInfo: userInfo) else { return nil }
    self.link = link
    self.messageId = Self.nonEmpty(userInfo[Key.messageId])
    self.sourceLabel = Self.nonEmpty(userInfo[Key.sourceLabel])
  }

  init(link: SessionLink, messageId: String? = nil, sourceLabel: String? = nil) {
    self.link = link
    self.messageId = messageId
    self.sourceLabel = sourceLabel
  }

  var refresh: ThreadRefresh { ThreadRefresh(sessionId: link.sessionId, messageId: messageId) }

  private static func nonEmpty(_ value: Any?) -> String? {
    guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }
    return string
  }
}

/// A request for the page showing `sessionId` to fetch its thread again and,
/// when `messageId` is set, bring that message into view.
nonisolated struct ThreadRefresh: Sendable, Equatable {
  var sessionId: String
  var messageId: String?
}

/// What a push does, decided from its payload and the page on screen. Pure, so
/// the rules are tested without a notification center.
nonisolated enum PushRoute: Equatable {
  /// Foreground delivery.
  enum Presentation: Equatable {
    /// Show the banner, with sound and badge.
    case banner
    /// The session is on screen: no banner.
    case suppress
    /// The session is on screen and this is a chat push: no banner, but the
    /// page fetches its thread so the message appears.
    case suppressAndRefresh(ThreadRefresh)
  }

  /// Not a session push: nothing to open.
  case none
  /// Open the session's page (the search-finished push, a deep link payload).
  case open(SessionLink)
  /// Open the session's page and show the new message on it.
  case openThread(SessionLink, ThreadRefresh)

  /// A tap on the notification, cold or warm start.
  static func tap(userInfo: [AnyHashable: Any]) -> PushRoute {
    if let push = ChatPush(userInfo: userInfo) { return .openThread(push.link, push.refresh) }
    if let link = SessionLink(userInfo: userInfo) { return .open(link) }
    return .none
  }

  /// A push arriving while the app is in front. The page for this session
  /// already on screen shows no banner (web's RunWatcher shows no toast for the
  /// run you are looking at); a chat push also refreshes that page.
  static func presentation(userInfo: [AnyHashable: Any], viewingSessionId: String?) -> Presentation {
    guard let viewingSessionId, let link = SessionLink(userInfo: userInfo), link.sessionId == viewingSessionId else { return .banner }
    if let push = ChatPush(userInfo: userInfo) { return .suppressAndRefresh(push.refresh) }
    return .suppress
  }
}
