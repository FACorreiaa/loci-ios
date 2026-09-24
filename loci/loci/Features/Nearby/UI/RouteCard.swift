import LociConnectProto
import MapKit
import SwiftUI

/// The route to the tapped place, pinned above the Near me list: the walk's
/// length and time, Go, and Open in Maps; while following, what is left and
/// End; on arrival, a word and Done.
struct RouteCard: View {
  let navigator: WalkNavigator
  let steps: String?
  let canGo: Bool
  let onGo: () -> Void
  let onEnd: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      if let arrived = navigator.arrivedAt {
        Image(systemName: "flag.checkered").font(.title2).foregroundStyle(Color.lociForest)
        VStack(alignment: .leading, spacing: 2) {
          Text("You're at \(arrived)").font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
          if let steps { Text(steps).lociCoordStyle(10) }
        }
        Spacer()
        Button("Done", action: onEnd).buttonStyle(.bordered).tint(.lociForest)
      } else if let poi = navigator.destination {
        VStack(alignment: .leading, spacing: 3) {
          Text(poi.name).font(.lociHeadline(16)).foregroundStyle(Color.lociInk).lineLimit(1)
          Text(summary).lociCoordStyle(10).contentTransition(.numericText())
          if navigator.isStraightLine {
            Text("No walking route — straight line").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
          }
          if !canGo {
            Text("Allow location in Settings to follow the route").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
          }
        }
        Spacer()
        if navigator.isNavigating {
          Button("End", systemImage: "xmark", action: onEnd).buttonStyle(.bordered).tint(.lociCoral)
        } else {
          Button {
            openInMaps(poi.name, poi.latitude, poi.longitude)
          } label: {
            Image(systemName: "map")
          }
          .buttonStyle(.bordered).tint(.lociForest)
          .accessibilityLabel("Open in Maps")
          Button("Go", systemImage: "figure.walk", action: onGo)
            .buttonStyle(.borderedProminent).tint(.lociForest)
            .disabled(!canGo || navigator.leg == nil)
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(Color.lociSage.opacity(0.5))
    .animation(LociTheme.selectionSettle, value: navigator.isNavigating)
  }

  private var summary: String {
    if navigator.isLoading, navigator.leg == nil { return "Finding a walking route…" }
    guard navigator.leg != nil else { return "" }
    let meters = NearbyWalkAttributes.ContentState.format(meters: navigator.remainingMeters)
    let time = NearbyWalkAttributes.ContentState.format(eta: navigator.eta)
    if navigator.isNavigating {
      return [meters + " to go", time, steps].compactMap { $0 }.joined(separator: " · ")
    }
    return "\(time) · \(meters) walk"
  }

  /// The same walking hand-off as PlaceDetailSheet.
  private func openInMaps(_ name: String, _ latitude: Double, _ longitude: Double) {
    let item = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
    item.name = name
    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
  }
}
