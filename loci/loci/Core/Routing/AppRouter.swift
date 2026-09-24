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
  /// Hosts whose result links open in the app (Universal Links, `applinks:` in loci.entitlements).
  public static let webHosts: Set<String> = ["lociai.fyi", "www.lociai.fyi"]

  /// `loci://itinerary?sessionId=…` (notifications, OAuth-era deep links) or
  /// `https://lociai.fyi/itinerary?sessionId=…` (a shared web link). Web's
  /// `/nearme` has no page of its own here; its session opens like an itinerary.
  public init?(url: URL) {
    let destination: SearchDestination?
    switch url.scheme?.lowercased() {
    case "loci":
      destination = url.host().flatMap(SearchDestination.init(rawValue:))
    case "https":
      guard let host = url.host()?.lowercased(), Self.webHosts.contains(host) else { return nil }
      let route = url.pathComponents.dropFirst().first ?? ""
      destination = route == "nearme" ? .itinerary : SearchDestination(rawValue: route)
    default:
      destination = nil
    }
    guard let destination else { return nil }
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

/// A signed-in page to open from a link: web's `/lists/:id`, `/packs/:slug`,
/// `/trips/:id`, `/recents` and `/contribute`. Parsed after `SessionLink`, so a
/// result link keeps its meaning. The AASA entries for the https form ship
/// with the web side (plan Phase 8); until then only `loci://` reaches the app.
public nonisolated enum AppLink: Sendable, Equatable, Hashable {
  case list(id: String)
  case pack(slug: String)
  case trip(id: String)
  case recents
  case contribute

  /// `loci://lists/abc` (the host is the route, as in `SessionLink`) or
  /// `https://lociai.fyi/lists/abc`. Anything with a missing id or extra
  /// segments is nil, so the link stays in Safari.
  public init?(url: URL) {
    var segments: [String]
    switch url.scheme?.lowercased() {
    case "loci":
      guard let host = url.host(), !host.isEmpty else { return nil }
      segments = [host] + url.pathComponents.dropFirst()
    case "https":
      guard let host = url.host()?.lowercased(), SessionLink.webHosts.contains(host) else { return nil }
      segments = Array(url.pathComponents.dropFirst())
    default:
      return nil
    }
    segments.removeAll { $0.isEmpty }
    switch (segments.first?.lowercased(), segments.count) {
    case ("lists", 2): self = .list(id: segments[1])
    case ("packs", 2): self = .pack(slug: segments[1])
    case ("trips", 2): self = .trip(id: segments[1])
    case ("recents", 1): self = .recents
    case ("contribute", 1): self = .contribute
    default: return nil
    }
  }
}

/// App-wide navigation requests that arrive from outside a view: deep links and
/// notification taps. Views observe `pendingSession` and clear it once shown.
@MainActor @Observable public final class AppRouter {
  public static let shared = AppRouter()

  public enum Tab: Hashable { case discover, calendar, assistant, saved, profile }

  public var selectedTab: Tab = .discover
  public var pendingSession: SessionLink?
  /// A page from an `AppLink`, taken by the tab `tab(for:)` names (`takeLink`).
  public var pendingLink: AppLink?
  /// A thread to fetch again, set by a chat push. The page showing that session
  /// takes it (`takeThreadRefresh`), whether it was already open or opens now.
  var threadRefresh: ThreadRefresh?
  /// Bumped by "New chat" on a results page: Ask Loci pops to its root and
  /// puts the cursor in its composer, whichever tab the page was on.
  public private(set) var newChatRequest = 0

  /// Returns true when the URL was a Loci route; false lets other handlers see it.
  @discardableResult public func open(_ url: URL) -> Bool {
    if let link = SessionLink(url: url) {
      open(link)
      return true
    }
    guard let link = AppLink(url: url) else { return false }
    open(link)
    return true
  }

  public func open(_ link: AppLink) {
    selectedTab = Self.tab(for: link)
    pendingLink = link
  }

  /// The tab that owns a page. Trips hang off Calendar; the You hub is Profile.
  static func tab(for link: AppLink) -> Tab {
    switch link {
    case .list: .saved
    case .pack: .discover
    case .trip: .calendar
    case .recents, .contribute: .profile
    }
  }

  /// The pending link when `tab` owns it, cleared so it opens once.
  func takeLink(for tab: Tab) -> AppLink? {
    guard let link = pendingLink, Self.tab(for: link) == tab else { return nil }
    pendingLink = nil
    return link
  }

  public func startNewChat() {
    selectedTab = .assistant
    newChatRequest += 1
  }

  public func open(_ link: SessionLink) {
    selectedTab = .assistant
    pendingSession = link
  }

  /// Open a session and show a message the agent just posted in it.
  func open(_ link: SessionLink, refresh: ThreadRefresh) {
    threadRefresh = refresh
    open(link)
  }

  /// Ask the page showing `refresh.sessionId` to fetch its thread again.
  func refreshThread(_ refresh: ThreadRefresh) {
    threadRefresh = refresh
  }

  /// The pending refresh for `sessionId`, cleared so it runs once.
  func takeThreadRefresh(for sessionId: String) -> ThreadRefresh? {
    guard let refresh = threadRefresh, refresh.sessionId == sessionId else { return nil }
    threadRefresh = nil
    return refresh
  }
}
