@preconcurrency import ActivityKit
import CoreLocation
import Foundation
import LociConnectProto
import Observation

/// A walk on the Near me screen: steps and distance from the pedometer, a
/// geofence around each place on the map, and a Live Activity on the Lock
/// Screen and Dynamic Island. Starts and stops with one button, so every
/// permission is asked at the moment it is needed.
@MainActor @Observable final class NearbyWalk {
  static let shared = NearbyWalk()

  let tracker = WalkTracker()
  private(set) var isActive = false
  private(set) var startedAt: Date?
  private(set) var coordinate: CLLocationCoordinate2D?
  private(set) var places: [Loci_Poi_POIDetailedInfo] = []

  private let proximity = POIProximityMonitor()
  // ActivityKit's Activity is not marked Sendable, though update/end are safe to
  // call from anywhere; the @preconcurrency import keeps that a warning.
  private var activity: Activity<NearbyWalkAttributes>?
  private var locationTask: Task<Void, Never>?
  private var lastActivityUpdate = Date.distantPast

  var liveActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

  func start(places: [Loci_Poi_POIDetailedInfo], radiusKm: Int) async {
    guard !isActive else { return }
    isActive = true
    startedAt = Date()
    self.places = places
    tracker.start()
    await proximity.arm(places: places, from: coordinate)
    startActivity(radiusKm: radiusKm)
    // Keep a location session open for the whole walk: geofences and the
    // "nearest place" need it, and with the `location` background mode it is
    // what keeps the walk alive when the phone is locked.
    locationTask = Task { [weak self] in
      let session = CLServiceSession(authorization: .whenInUse)
      defer { session.invalidate() }
      do {
        for try await update in CLLocationUpdate.liveUpdates() {
          guard let self else { return }
          if let location = update.location { self.coordinate = location.coordinate }
          self.refreshActivity()
        }
      } catch {}
    }
  }

  /// New results arrived while walking: fence the new places.
  func update(places: [Loci_Poi_POIDetailedInfo]) async {
    guard isActive else { return }
    self.places = places
    await proximity.arm(places: places, from: coordinate)
    refreshActivity(force: true)
  }

  func stop() async {
    guard isActive else { return }
    isActive = false
    locationTask?.cancel()
    locationTask = nil
    tracker.stop()
    await proximity.disarm()
    if let activity {
      self.activity = nil
      let state = contentState
      await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
    }
  }

  // MARK: - Live Activity

  private var contentState: NearbyWalkAttributes.ContentState {
    let nearest = Self.nearest(of: places, to: coordinate)
    return NearbyWalkAttributes.ContentState(
      steps: tracker.steps,
      distanceMeters: tracker.distanceMeters,
      placesNearby: places.count,
      nearestName: nearest?.name,
      nearestMeters: nearest?.meters
    )
  }

  private func startActivity(radiusKm: Int) {
    guard liveActivitiesEnabled, let startedAt else { return }
    let attributes = NearbyWalkAttributes(startedAt: startedAt, radiusKm: radiusKm)
    activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: contentState, staleDate: nil), pushType: nil)
  }

  /// At most one update every few seconds: ActivityKit throttles anyway, and
  /// the Lock Screen does not need every step.
  func refreshActivity(force: Bool = false) {
    guard let activity, force || Date().timeIntervalSince(lastActivityUpdate) > 5 else { return }
    lastActivityUpdate = Date()
    let state = contentState
    Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
  }

  nonisolated static func nearest(of places: [Loci_Poi_POIDetailedInfo], to coordinate: CLLocationCoordinate2D?) -> (name: String, meters: Double)? {
    guard let coordinate else { return nil }
    let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    return places.filter { $0.hasLatitude && $0.hasLongitude }
      .map { (name: $0.name, meters: CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here)) }
      .min { $0.meters < $1.meters }
  }
}
