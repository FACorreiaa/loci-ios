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
    pedometer.startUpdates(from: Date()) { [weak self] data, error in
      Task { @MainActor in
        guard let self else { return }
        if let error {
          // Permission refused (or motion unavailable): stop counting, keep the walk.
          if (error as NSError).code == CMErrorMotionActivityNotAuthorized.rawValue { self.deniedByUser = true }
          return
        }
        guard let data else { return }
        self.steps = data.numberOfSteps.intValue
        if let distance = data.distance { self.distanceMeters = distance.doubleValue }
      }
    }
  }

  func stop() {
    guard isRunning else { return }
    pedometer.stopUpdates()
    isRunning = false
  }
}
