import CoreLocation

/// One location fix, asking for when-in-use permission the first time.
enum CurrentLocation {
  enum Failure: LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
      switch self {
      case .denied: "Location access is off. Turn it on in Settings to search near you."
      case .unavailable: "Your location isn't available right now."
      }
    }
  }

  static func fetch(timeout: Duration = .seconds(15)) async throws -> CLLocationCoordinate2D {
    let session = CLServiceSession(authorization: .whenInUse)
    defer { session.invalidate() }
    return try await withThrowingTaskGroup(of: CLLocationCoordinate2D.self) { group in
      group.addTask {
        for try await update in CLLocationUpdate.liveUpdates() {
          if update.authorizationDenied || update.authorizationDeniedGlobally { throw Failure.denied }
          if let location = update.location { return location.coordinate }
        }
        throw Failure.unavailable
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw Failure.unavailable
      }
      defer { group.cancelAll() }
      guard let first = try await group.next() else { throw Failure.unavailable }
      return first
    }
  }
}
