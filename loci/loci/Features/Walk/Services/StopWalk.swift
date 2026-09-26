@preconcurrency import ActivityKit
import CoreLocation
import Foundation
import LociConnectProto
import Observation
import UIKit
import UserNotifications

/// Walking a day stop by stop: directions to one stop at a time, a pause at
/// each ("You're at X"), and the next leg only when the person taps Walk to
/// next. The directions, rerouting and arrival come from `WalkNavigator`,
/// the same as Near me. Trip-day mode is separate and may run alongside.
@MainActor @Observable final class StopWalk {
  static let shared = StopWalk()

  enum Phase: Equatable { case idle, walking, arrived, done }

  struct Summary: Equatable {
    var visited: Int
    var skipped: Int
    var meters: Double
    var steps: Int
  }

  let navigator: WalkNavigator
  let tracker = WalkTracker()
  private(set) var day: WalkDay?
  /// The stop being walked to, or the one just reached.
  private(set) var index = 0
  private(set) var phase = Phase.idle
  private(set) var visited: Set<Int> = []
  private(set) var skipped: Set<Int> = []
  private(set) var location: CLLocation?

  /// Off in tests: no pedometer, location loop, Live Activity or notifications.
  let live: Bool
  /// Where the walk last knew the person was, for routes before the first fix.
  private var origin: CLLocationCoordinate2D?
  private var activity: Activity<NearbyWalkAttributes>?
  private var locationTask: Task<Void, Never>?
  private var lastActivityUpdate = Date.distantPast

  init(navigator: WalkNavigator = WalkNavigator(), live: Bool = true) {
    self.navigator = navigator
    self.live = live
  }

  var stops: [WalkStop] { day?.stops ?? [] }

  /// The next stop after the current one, passing over skipped stops.
  var upcoming: Int? { Self.nextIndex(after: index, count: stops.count, skipped: skipped) }

  var progressText: String { "\(index + 1) of \(stops.count)" }

  var summary: Summary {
    Summary(visited: visited.count, skipped: skipped.count, meters: tracker.distanceMeters, steps: tracker.steps)
  }

  func isWalking(key: String) -> Bool { phase != .idle && day?.id == key }

  func start(_ day: WalkDay, from here: CLLocationCoordinate2D) async {
    await end()
    guard !day.stops.isEmpty else { return }
    self.day = day
    origin = here
    if live { await startLive(title: day.title) }
    await walk(to: 0)
  }

  /// A location fix: trims the route, and on arrival pauses at the stop.
  func ingest(_ location: CLLocation) async {
    self.location = location
    origin = location.coordinate
    guard phase == .walking else { return }
    navigator.ingest(location)
    guard navigator.arrivedAt != nil else { return }
    navigator.dismissArrival()
    visited.insert(index)
    await notifyArrival()
    await arrived()
    refreshActivity(force: true)
  }

  func walkToNext() async {
    guard phase == .arrived, let next = upcoming else { return }
    await walk(to: next)
  }

  /// Leave the next stop out and preview the one after it.
  func skip() async {
    guard phase == .arrived, let next = upcoming else { return }
    skipped.insert(next)
    await arrived()
    refreshActivity(force: true)
  }

  func jump(to target: Int) async {
    guard stops.indices.contains(target), phase != .idle else { return }
    skipped.remove(target)
    await walk(to: target)
  }

  func end() async {
    if live { await stopLive() }
    navigator.end()
    day = nil
    index = 0
    phase = .idle
    visited = []
    skipped = []
    location = nil
    origin = nil
  }

  nonisolated static func nextIndex(after current: Int, count: Int, skipped: Set<Int>) -> Int? {
    guard current + 1 < count else { return nil }
    return (current + 1..<count).first { !skipped.contains($0) }
  }

  // MARK: - Lock Screen, location, notifications

  nonisolated static func contentState(
    phase: Phase,
    stopName: String?,
    progress: String,
    meters: Double?,
    eta: TimeInterval?,
    steps: Int,
    walked: Double
  ) -> NearbyWalkAttributes.ContentState {
    switch phase {
    case .walking:
      return NearbyWalkAttributes.ContentState(
        steps: steps,
        distanceMeters: walked,
        placesNearby: 0,
        destinationName: stopName,
        destinationMeters: meters,
        etaSeconds: eta,
        stopProgress: progress
      )
    case .arrived:
      return NearbyWalkAttributes.ContentState(
        steps: steps,
        distanceMeters: walked,
        placesNearby: 0,
        destinationName: stopName.map { "At \($0)" },
        stopProgress: progress
      )
    case .done, .idle:
      return NearbyWalkAttributes.ContentState(steps: steps, distanceMeters: walked, placesNearby: 0, destinationName: "Day walked")
    }
  }

  private var currentContent: NearbyWalkAttributes.ContentState {
    Self.contentState(
      phase: phase,
      stopName: stops.indices.contains(index) ? stops[index].name : nil,
      progress: progressText,
      meters: navigator.isNavigating ? navigator.remainingMeters : nil,
      eta: navigator.isNavigating ? navigator.eta : nil,
      steps: tracker.steps,
      walked: tracker.distanceMeters
    )
  }

  /// At most one update every few seconds, like the Near me walk.
  func refreshActivity(force: Bool = false) {
    guard let activity, force || Date().timeIntervalSince(lastActivityUpdate) > 5 else { return }
    lastActivityUpdate = Date()
    let state = currentContent
    Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
  }

  private func startLive(title: String) async {
    await NearbyWalk.shared.stop()
    tracker.start()
    if ActivityAuthorizationInfo().areActivitiesEnabled {
      let attributes = NearbyWalkAttributes(startedAt: Date(), radiusKm: 0, title: title)
      activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: currentContent, staleDate: nil), pushType: nil)
    }
    // Same loop as NearbyWalk: with the `location` background mode it keeps the
    // walk going, and arrival detected, while the phone is locked.
    locationTask = Task { [weak self] in
      let session = CLServiceSession(authorization: .whenInUse)
      defer { session.invalidate() }
      do {
        for try await update in CLLocationUpdate.liveUpdates() {
          guard let self else { return }
          if let location = update.location { await self.ingest(location) }
          self.refreshActivity()
        }
      } catch {}
    }
  }

  private func stopLive() async {
    locationTask?.cancel()
    locationTask = nil
    tracker.stop()
    if let activity {
      self.activity = nil
      let state = currentContent
      await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
    }
  }

  /// Arrival with the app in the background: say so on the Lock Screen.
  private func notifyArrival() async {
    guard live, UIApplication.shared.applicationState != .active, stops.indices.contains(index) else { return }
    let content = UNMutableNotificationContent()
    content.title = "You're at \(stops[index].name) (\(progressText))"
    content.body = upcoming.map { "Next: \(stops[$0].name). Open Loci to walk on." } ?? "That was the last stop."
    content.sound = .default
    content.threadIdentifier = "walk-day"
    let request = UNNotificationRequest(identifier: "walk-day-\(index)", content: content, trigger: nil)
    try? await UNUserNotificationCenter.current().add(request)
  }

  // MARK: - Private

  private func walk(to target: Int) async {
    index = target
    phase = .walking
    let stop = stops[target]
    if navigator.destination?.stableID != stop.poi.stableID || navigator.leg == nil, let origin {
      await navigator.preview(to: stop.poi, from: origin)
    }
    navigator.start()
    refreshActivity(force: true)
  }

  /// At `index`: preview the next stop, or finish the day.
  private func arrived() async {
    guard let next = upcoming else {
      navigator.end()
      phase = .done
      return
    }
    phase = .arrived
    if let origin { await navigator.preview(to: stops[next].poi, from: origin) }
  }
}
