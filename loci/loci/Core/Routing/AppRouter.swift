import Foundation
import Observation

/// The result screens a search lands on. Raw values are the web routes
/// (loci-client/src/lib/streaming-service.ts `getDomainRoute`).
public nonisolated enum SearchDestination: String, Sendable, Equatable, CaseIterable {
  case itinerary
  case hotels
  case restaurants
  case activities

  /// Map the server's domain string (StartPayload.domain, or the `domain` query
  /// item) to a screen, exactly as web does: general and itinerary share a page.
  public init(domain: String) {
    switch domain.lowercased() {
    case "accommodation", "hotels", "domain_type_accommodation": self = .hotels
    case "dining", "restaurants", "domain_type_dining": self = .restaurants
    case "activities", "domain_type_activities": self = .activities
    default: self = .itinerary
    }
  }
}

/// A search session to open: `/itinerary?sessionId=&cityName=&domain=` and siblings.
public nonisolated struct SessionLink: Sendable, Equatable, Hashable {
  public var destination: SearchDestination
  public var sessionId: String
  public var cityName: String?
  public var domain: String?

  /// Keys shared by the deep link, the local notification's userInfo and the
  /// planned server push payload.
  public enum Key {
    public static let sessionId = "sessionId"
    public static let cityName = "cityName"
    public static let domain = "domain"
  }

  public init(destination: SearchDestination, sessionId: String, cityName: String? = nil, domain: String? = nil) {
    self.destination = destination
    self.sessionId = sessionId
    self.cityName = cityName
    self.domain = domain
  }

  /// Parse `loci://itinerary?sessionId=…` (the host is the web route's first path
  /// segment). Returns nil for anything else, including `loci://oauth2redirect/…`,
  /// which belongs to ASWebAuthenticationSession.
  public init?(url: URL) {
    guard url.scheme == "loci", let host = url.host(), let destination = SearchDestination(rawValue: host) else {
      return nil
    }
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func value(_ name: String) -> String? { items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 } }
    guard let sessionId = value(Key.sessionId) else { return nil }
    self.init(destination: destination, sessionId: sessionId, cityName: value(Key.cityName), domain: value(Key.domain))
  }

  /// Parse a notification's userInfo.
  public init?(userInfo: [AnyHashable: Any]) {
    guard let sessionId = userInfo[Key.sessionId] as? String, !sessionId.isEmpty else { return nil }
    let domain = userInfo[Key.domain] as? String
    self.init(
      destination: SearchDestination(domain: domain ?? ""),
      sessionId: sessionId,
      cityName: (userInfo[Key.cityName] as? String).flatMap { $0.isEmpty ? nil : $0 },
      domain: domain
    )
  }

  public var url: URL? {
    var components = URLComponents()
    components.scheme = "loci"
    components.host = destination.rawValue
    components.queryItems = [URLQueryItem(name: Key.sessionId, value: sessionId)]
    if let cityName { components.queryItems?.append(URLQueryItem(name: Key.cityName, value: cityName)) }
    if let domain { components.queryItems?.append(URLQueryItem(name: Key.domain, value: domain)) }
    return components.url
  }

  public var userInfo: [String: String] {
    var info = [Key.sessionId: sessionId]
    if let cityName { info[Key.cityName] = cityName }
    info[Key.domain] = domain ?? destination.rawValue
    return info
  }
}

/// App-wide navigation requests that arrive from outside a view: deep links and
/// notification taps. Views observe `pendingSession` and clear it once shown.
@MainActor @Observable public final class AppRouter {
  public static let shared = AppRouter()

  public enum Tab: Hashable { case discover, calendar, assistant, saved, profile }

  public var selectedTab: Tab = .discover
  public var pendingSession: SessionLink?

  /// Returns true when the URL was a Loci route; false lets other handlers see it.
  @discardableResult public func open(_ url: URL) -> Bool {
    guard let link = SessionLink(url: url) else { return false }
    open(link)
    return true
  }

  public func open(_ link: SessionLink) {
    selectedTab = .assistant
    pendingSession = link
  }
}
