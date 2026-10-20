import CoreLocation
import Foundation
import LociConnectProto
import UserNotifications

/// "Log places I visit on trips": while a trip day is under way, iOS's visit
/// monitoring notices where the phone stayed, and a stay at a planned stop or
/// a saved place asks "Were you at X?". Opt-in, this phone only, and only
/// with Always location. Nothing is logged without a yes.
@MainActor final class VisitLogger: NSObject, CLLocationManagerDelegate {
  static let shared = VisitLogger()
  nonisolated static let enabledKey = "loci_visit_logging"

  nonisolated static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

  private let manager = CLLocationManager()
  private var today: TodayFirst?
  private var favorites: [VisitCandidate] = []
  private let pending = PendingVisitStore()

  private override init() {
    super.init()
    manager.delegate = self
  }

  static func setEnabled(_ on: Bool) {
    UserDefaults.standard.set(on, forKey: enabledKey)
    if on { LocationUpgrade.requestAlways() }
    Task { await shared.refresh() }
  }

  /// Runs only when switched on, with Always location, on a trip day.
  nonisolated static func shouldRun(enabled: Bool, authorization: CLAuthorizationStatus, today: TodayFirst?) -> Bool {
    enabled && authorization == .authorizedAlways && today != nil
  }

  nonisolated enum MonitorAction { case start, stop }

  /// What to do with iOS's visit monitoring. iOS keeps it on across launches,
  /// so stopping never depends on this process having started it.
  nonisolated static func monitorAction(shouldRun: Bool) -> MonitorAction { shouldRun ? .start : .stop }

  /// On launch, on every return to the foreground, and on every stay iOS
  /// reports. Starting or stopping twice is harmless.
  func refresh(now: Date = Date()) async {
    let trips = await LocalCache.shared.get(Loci_Trip_ListTripsResponse.self, kind: .trips, id: "all")?.value.trips ?? []
    today = TodayFirst.pick(trips: trips, now: now)
    let run = Self.shouldRun(enabled: Self.isEnabled, authorization: manager.authorizationStatus, today: today)
    guard Self.monitorAction(shouldRun: run) == .start, let today else {
      manager.stopMonitoringVisits()
      return
    }
    manager.startMonitoringVisits()
    var request = Loci_Favorites_V1_GetFavoritesRequest()
    request.limit = 200
    let sent = request
    if let saved = try? await rpc("", sent, { await SavedAPI.favorites.getFavorites(request: $0, headers: [:]) }) {
      favorites = VisitMatch.candidates(favorites: saved.favorites, city: Self.city(today))
    }
  }

  private static func city(_ today: TodayFirst) -> String {
    today.day.cityName.isEmpty ? today.trip.cityName : today.day.cityName
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    // An arrival only: iOS reports the departure of the same stay later.
    guard visit.arrivalDate != .distantPast, visit.departureDate == .distantFuture else { return }
    let coordinate = visit.coordinate
    let arrival = visit.arrivalDate
    let accuracy = visit.horizontalAccuracy
    Task { @MainActor in await self.arrived(at: coordinate, on: arrival, accuracy: accuracy) }
  }

  private func arrived(at coordinate: CLLocationCoordinate2D, on arrival: Date, accuracy: CLLocationAccuracy) async {
    // The trip day is read at the arrival, not remembered: the app may have
    // stayed suspended past the trip's last day, and iOS can report a stay
    // late or relaunch the app for it.
    await refresh(now: arrival)
    guard Self.shouldRun(enabled: Self.isEnabled, authorization: manager.authorizationStatus, today: today), let today else { return }
    let stops = VisitMatch.candidates(stops: today.day.stops, city: Self.city(today))
    guard let place = VisitMatch.nearest(to: coordinate, stops: stops, favorites: favorites) else { return }
    let visit = PendingVisit(
      id: UUID().uuidString,
      place: place,
      tripID: today.trip.id,
      arrival: arrival,
      latitude: coordinate.latitude,
      longitude: coordinate.longitude,
      accuracy: max(accuracy, 0),
    )
    guard pending.add(visit) else { return }
    await VisitPrompt.schedule(visit)
  }
}

/// The local notification that asks "Were you at X?". Yes records the visit
/// without opening the app; No forgets it.
nonisolated enum VisitPrompt {
  static let yes = "visit_yes"
  static let no = "visit_no"

  static func identifier(_ id: String) -> String { "visit-\(id)" }

  static func schedule(_ visit: PendingVisit) async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
    let content = UNMutableNotificationContent()
    content.title = "Were you at \(visit.place.name)?"
    content.body = "Yes adds it to your trip journal."
    content.categoryIdentifier = NotificationCategory.lociVisit
    content.threadIdentifier = "visit"
    content.userInfo = ["visitID": visit.id, "tripId": visit.tripID]
    try? await center.add(UNNotificationRequest(identifier: identifier(visit.id), content: content, trigger: nil))
  }

  /// A notification answered. Yes records it (a failure keeps it for the
  /// journal to ask again); No forgets it; a tap leaves it for the journal.
  static func handle(
    actionIdentifier: String,
    visitID: String,
    store: PendingVisitStore = PendingVisitStore(),
    recorder: any VisitRecorder = ConnectVisitRecorder(),
  ) async {
    switch actionIdentifier {
    case yes: try? await store.confirm(id: visitID, recorder: recorder)
    case no: store.dismiss(id: visitID)
    default: break
    }
  }
}
