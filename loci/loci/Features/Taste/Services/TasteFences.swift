import CoreLocation
import Foundation
import LociConnectProto
import UserNotifications

/// Which saved places to fence on a trip day: the ones in today's city that
/// fit the traveller (match ≥ 60%), best first, within what CLMonitor has left.
nonisolated enum TasteFencePlan {
  static let minScore: Float = 0.6
  static let maxFences = 15

  static func pick(_ favorites: [Loci_Favorites_V1_FavoriteItem], city: String, budget: Int) -> [Loci_Favorites_V1_FavoriteItem] {
    let city = normalized(city)
    guard !city.isEmpty, budget > 0 else { return [] }
    var seen = Set<String>()
    let fits = favorites.filter {
      $0.contentType != .itinerary && normalized($0.cityName) == city && $0.hasTasteMatch && $0.tasteMatch.score >= minScore
        && ($0.latitude != 0 || $0.longitude != 0) && seen.insert($0.itemID).inserted
    }
    return Array(fits.sorted { $0.tasteMatch.score > $1.tasteMatch.score }.prefix(min(maxFences, budget)))
  }

  private static func normalized(_ city: String) -> String { city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}

/// CLMonitor conditions in use per monitor name. iOS allows the app 20 in
/// all, and the walk and the trip day come first.
nonisolated struct FenceBudget {
  var used: [String: Int] = [:]

  func available(for name: String) -> Int {
    max(0, POIProximityMonitor.maxConditions - used.filter { $0.key != name }.values.reduce(0, +))
  }
}

/// "You're near a saved place that fits you" during a trip. Opt-in
/// (`nearby_fits`), and only with Always location: the fences have to fire
/// with the app in the background.
@MainActor final class TasteFences {
  static let shared = TasteFences()
  /// Letters and digits only; CLMonitor aborts on anything else.
  nonisolated static let name = "lociTasteFences"
  nonisolated static let radiusMeters: CLLocationDistance = 150
  nonisolated static let enabledKey = "loci_nearby_fits"
  /// Shared with POIProximityMonitor, which records what it holds.
  static var budget = FenceBudget()

  nonisolated static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

  private var monitor: CLMonitor?
  private var eventsTask: Task<Void, Never>?
  private var fenced: [String: Loci_Favorites_V1_FavoriteItem] = [:]
  private let limiter = NudgeLimiter()

  /// The account setting, mirrored on the device; off clears the fences.
  static func setEnabled(_ on: Bool) {
    UserDefaults.standard.set(on, forKey: enabledKey)
    Task { await on ? shared.refresh() : shared.disarm() }
  }

  /// On launch and on every return to the foreground: fence today's fits, or
  /// clear the fences when there is no trip day, no permission or no room.
  func refresh(now: Date = Date()) async {
    guard Self.isEnabled, CLLocationManager().authorizationStatus == .authorizedAlways else {
      await disarm()
      return
    }
    let trips = await LocalCache.shared.get(Loci_Trip_ListTripsResponse.self, kind: .trips, id: "all")?.value.trips ?? []
    guard let today = TodayFirst.pick(trips: trips, now: now) else {
      await disarm()
      return
    }
    let city = today.day.cityName.isEmpty ? today.trip.cityName : today.day.cityName
    var request = Loci_Favorites_V1_GetFavoritesRequest()
    request.limit = 200
    let sent = request
    guard let saved = try? await rpc("", sent) { await SavedAPI.favorites.getFavorites(request: $0, headers: [:]) } else { return }
    await arm(TasteFencePlan.pick(saved.favorites, city: city, budget: Self.budget.available(for: Self.name)))
  }

  func disarm() async {
    eventsTask?.cancel()
    eventsTask = nil
    fenced = [:]
    Self.budget.used[Self.name] = 0
    guard let monitor else { return }
    for identifier in await monitor.identifiers { await monitor.remove(identifier) }
  }

  private func arm(_ places: [Loci_Favorites_V1_FavoriteItem]) async {
    guard !places.isEmpty else {
      await disarm()
      return
    }
    if monitor == nil { monitor = await CLMonitor(Self.name) }
    guard let monitor else { return }
    let wanted = Set(places.map(\.itemID))
    for identifier in await monitor.identifiers where !wanted.contains(identifier) { await monitor.remove(identifier) }
    for place in places {
      fenced[place.itemID] = place
      guard await monitor.record(for: place.itemID) == nil else { continue }
      let center = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
      let condition = CLMonitor.CircularGeographicCondition(center: center, radius: Self.radiusMeters)
      await monitor.add(condition, identifier: place.itemID, assuming: .unsatisfied)
    }
    Self.budget.used[Self.name] = places.count
    if eventsTask == nil {
      eventsTask = Task { [weak self] in
        do {
          for try await event in await monitor.events {
            guard let self, event.state == .satisfied else { continue }
            await self.arrived(at: event.identifier)
          }
        } catch {}
      }
    }
  }

  private func arrived(at identifier: String) async {
    guard let place = fenced[identifier], limiter.allow(poiID: identifier) else { return }
    let content = UNMutableNotificationContent()
    content.title = "You're near \(place.itemName)"
    content.body = "\(Int((place.tasteMatch.score * 100).rounded()))% your match — one of your saved places."
    content.sound = .default
    content.threadIdentifier = "taste-fences"
    content.userInfo = ["origin": "nearby_fits", "poiId": identifier]
    try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "fits-\(identifier)", content: content, trigger: nil))
  }
}
