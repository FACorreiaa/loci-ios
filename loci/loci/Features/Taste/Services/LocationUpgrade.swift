import CoreLocation

/// Asks once for Always location, after the traveller turns on "Saved places
/// nearby". iOS shows the upgrade prompt only to an app that already has
/// While Using, and only once; after that the switch lives in Settings.
@MainActor enum LocationUpgrade {
  /// Kept alive: a released manager drops its prompt.
  private static let manager = CLLocationManager()

  static func requestAlways() {
    switch manager.authorizationStatus {
    case .notDetermined, .authorizedWhenInUse: manager.requestAlwaysAuthorization()
    default: break
    }
  }
}
