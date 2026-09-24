import CoreLocation
import Foundation
import LociConnectProto
import UserNotifications

/// Geofences around the places on the Near me map. Walking into one posts a
/// local notification once per walk ("You're 40 m from …"). Built on
/// `CLMonitor`, which keeps its conditions across launches, so a walk that
/// stops always clears them.
@MainActor final class POIProximityMonitor {
  /// CLMonitor accepts up to 20 conditions.
  nonisolated static let maxConditions = 20
  nonisolated static let radiusMeters: CLLocationDistance = 60

  /// Each CLMonitor name keeps its own conditions, so the Near me walk and a
  /// trip day do not clear each other's fences.
  private let name: String
  /// Called with the place's `stableID` on arrival, besides the notification.
  var onArrive: ((String) -> Void)?

  init(name: String = "loci-nearby-walk") {
    self.name = name
  }

  private var monitor: CLMonitor?
  private var eventsTask: Task<Void, Never>?
  private var names: [String: String] = [:]
  private var notified: Set<String> = []

  /// Fence the `maxConditions` places nearest to `origin`.
  func arm(places: [Loci_Poi_POIDetailedInfo], from origin: CLLocationCoordinate2D?) async {
    if monitor == nil { monitor = await CLMonitor(name) }
    guard let monitor else { return }
    let chosen = Self.select(places: places, from: origin)

    // Drop fences that are no longer on the list, then add the new ones.
    let wanted = Set(chosen.map(\.stableID))
    for identifier in await monitor.identifiers where !wanted.contains(identifier) { await monitor.remove(identifier) }
    for poi in chosen {
      names[poi.stableID] = poi.name
      guard await monitor.record(for: poi.stableID) == nil else { continue }
      let condition = CLMonitor.CircularGeographicCondition(
        center: CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude),
        radius: Self.radiusMeters
      )
      await monitor.add(condition, identifier: poi.stableID, assuming: .unsatisfied)
    }

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

  func disarm() async {
    eventsTask?.cancel()
    eventsTask = nil
    notified = []
    guard let monitor else { return }
    for identifier in await monitor.identifiers { await monitor.remove(identifier) }
  }

  /// Nearest first, without repeats, capped at what CLMonitor allows.
  nonisolated static func select(places: [Loci_Poi_POIDetailedInfo], from origin: CLLocationCoordinate2D?) -> [Loci_Poi_POIDetailedInfo] {
    var seen = Set<String>()
    let unique = places.filter { $0.hasLatitude && $0.hasLongitude && seen.insert($0.stableID).inserted }
    guard let origin else { return Array(unique.prefix(maxConditions)) }
    let here = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
    return Array(
      unique.sorted {
        CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here)
          < CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: here)
      }.prefix(maxConditions)
    )
  }

  private func arrived(at identifier: String) async {
    onArrive?(identifier)
    guard notified.insert(identifier).inserted, let name = names[identifier] else { return }
    let content = UNMutableNotificationContent()
    content.title = "You're near \(name)"
    content.body = "About \(Int(Self.radiusMeters)) m away. Worth a look?"
    content.sound = .default
    content.threadIdentifier = "nearby-walk"
    content.userInfo = ["poi": name]
    try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "near-\(identifier)", content: content, trigger: nil))
  }
}
