import CoreMotion
import Foundation
import Observation

/// Live step count and distance from the phone's motion coprocessor
/// (`CMPedometer`). No HealthKit: nothing is read from or written to Health,
/// and the only prompt is Motion & Fitness, asked the first time a walk starts.
@MainActor @Observable final class WalkTracker {
  private(set) var steps = 0
  private(set) var distanceMeters: Double = 0
  private(set) var isRunning = false
  private(set) var isAvailable = CMPedometer.isStepCountingAvailable()
  private(set) var deniedByUser = false

  private let pedometer = CMPedometer()

  var stepsText: String { NearbyWalkAttributes.ContentState(steps: steps, distanceMeters: distanceMeters, placesNearby: 0).stepsText }
  var distanceText: String { NearbyWalkAttributes.ContentState.format(meters: distanceMeters) }

  func start() {
    guard isAvailable, !isRunning else { return }
    steps = 0
    distanceMeters = 0
    deniedByUser = false
    isRunning = true
    // CoreMotion calls this on its own queue: read plain values here and hop
    // to the main actor with those, never with `CMPedometerData` itself.
    pedometer.startUpdates(from: Date()) { @Sendable [weak self] data, error in
      if let error {
        // Permission refused (or motion unavailable): stop counting, keep the walk.
        let denied = (error as NSError).code == CMErrorMotionActivityNotAuthorized.rawValue
        Task { @MainActor in self?.apply(denied: denied) }
        return
      }
      guard let data else { return }
      let steps = data.numberOfSteps.intValue
      let meters = data.distance?.doubleValue
      Task { @MainActor in self?.apply(steps: steps, meters: meters) }
    }
  }

  private func apply(denied: Bool) {
    if denied { deniedByUser = true }
  }

  private func apply(steps: Int, meters: Double?) {
    self.steps = steps
    if let meters { distanceMeters = meters }
  }

  func stop() {
    guard isRunning else { return }
    pedometer.stopUpdates()
    isRunning = false
  }
}
