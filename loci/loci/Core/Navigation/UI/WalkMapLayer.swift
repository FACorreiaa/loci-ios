import CoreLocation
import LociConnectProto
import MapKit
import SwiftUI

/// What every walking map draws: the walker figure while following a route
/// (the system dot otherwise), the route line, and a camera that rides behind
/// the walker. Shared by Near me and walking a day.
enum WalkMapLayer {
  @MapContentBuilder
  static func content(navigator: WalkNavigator, location: CLLocation?, heading: CLLocationDirection?, isMoving: Bool) -> some MapContent {
    if navigator.isNavigating, let location {
      Annotation("You", coordinate: location.coordinate, anchor: .bottom) {
        WalkerFigure(
          facesLeft: heading.map(WalkingRoute.facesLeft) ?? false,
          isMoving: isMoving,
          destinationName: navigator.destination?.name
        )
      }
      .annotationTitles(.hidden)
    } else {
      UserAnnotation()
    }
    if navigator.remaining.count > 1 {
      MapPolyline(coordinates: navigator.remaining)
        .stroke(
          Color.lociForest,
          style: navigator.isNavigating && !navigator.isStraightLine
            ? StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
            : StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [1, 10])
        )
    }
  }

  static func heading(location: CLLocation?, navigator: WalkNavigator) -> CLLocationDirection? {
    guard let location else { return nil }
    return WalkingRoute.heading(
      course: location.course,
      speed: location.speed,
      from: location.coordinate,
      toward: navigator.remaining.dropFirst().first ?? navigator.destinationCoordinate
    )
  }

  /// Moving by GPS, or the pedometer counted a step in the last few seconds.
  nonisolated static func isMoving(speed: CLLocationSpeed?, lastStepAt: Date, now: Date = Date()) -> Bool {
    (speed ?? 0) > 0.3 || now.timeIntervalSince(lastStepAt) < 3
  }

  /// Low and tilted behind the walker, looking the way they are heading.
  static func followCamera(at location: CLLocation, heading: CLLocationDirection?) -> MapCameraPosition {
    .camera(MapCamera(centerCoordinate: location.coordinate, distance: 400, heading: heading ?? 0, pitch: 60))
  }
}

/// Shown once the person pans away from the walker.
struct RecenterButton: View {
  let action: () -> Void

  var body: some View {
    Button("Recenter", systemImage: "location.north.line.fill", action: action)
      .lociProminentButton()
      .padding(.top, 8)
      .transition(.move(edge: .top).combined(with: .opacity))
  }
}
