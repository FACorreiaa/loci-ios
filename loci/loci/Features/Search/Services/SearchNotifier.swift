import Foundation
import UserNotifications

/// Local "your search finished" notifications. The userInfo keys are the deep
/// link's (`SessionLink.Key`), which are also the keys the planned server push
/// will carry, so a tap routes the same way whichever delivered it.
nonisolated struct SearchNotifier: Sendable {
  func post(link: SessionLink, succeeded: Bool, query: String) async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

    let content = UNMutableNotificationContent()
    content.title = Self.title(for: link, succeeded: succeeded)
    content.body = succeeded ? "Tap to see it." : "Tap to see what happened and try again."
    if !query.isEmpty { content.subtitle = query }
    content.sound = .default
    content.userInfo = link.userInfo
    content.threadIdentifier = "search"

    // One notification per session: a later post for the same search replaces it.
    let request = UNNotificationRequest(identifier: "search-\(link.sessionId)", content: content, trigger: nil)
    try? await center.add(request)
  }

  static func title(for link: SessionLink, succeeded: Bool) -> String {
    let place = link.cityName.map { " for \($0)" } ?? ""
    guard succeeded else { return "Your search\(place) didn't finish" }
    switch link.destination {
    case .itinerary: return "Your itinerary\(place) is ready"
    case .hotels: return "Hotels\(place) are ready"
    case .restaurants: return "Restaurants\(place) are ready"
    case .activities: return "Activities\(place) are ready"
    }
  }
}
