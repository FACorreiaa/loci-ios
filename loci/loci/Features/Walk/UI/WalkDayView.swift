import CoreLocation
import MapKit
import SwiftUI

/// Walk a day stop by stop, Near me style: the route to the next stop, the
/// walker, a camera that follows, and a pause at each stop.
struct WalkDayView: View {
  let day: WalkDay
  private let walk = StopWalk.shared
  @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
  @State private var following = true
  @State private var lastStepAt = Date.distantPast
  @State private var showList = false
  @State private var error: String?

  var body: some View {
    Map(position: $camera) {
      WalkMapLayer.content(
        navigator: walk.navigator,
        location: walk.location,
        heading: WalkMapLayer.heading(location: walk.location, navigator: walk.navigator),
        isMoving: WalkMapLayer.isMoving(speed: walk.location?.speed, lastStepAt: lastStepAt)
      )
      ForEach(Array(day.stops.enumerated()), id: \.element.id) { i, stop in
        Marker(stop.name, monogram: Text("\(i + 1)"), coordinate: stop.coordinate).tint(tint(i))
      }
    }
    .mapControls {
      MapUserLocationButton()
      MapCompass()
    }
    .overlay(alignment: .top) {
      if walk.navigator.isNavigating, !following { RecenterButton { follow() } }
    }
    .safeAreaInset(edge: .bottom) {
      WalkDayCard(walk: walk, withoutLocation: day.withoutLocation) { Task { await walk.end() } }
        .padding(.bottom, 8)
    }
    .navigationTitle(day.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Stops", systemImage: "list.number") { showList = true }.disabled(walk.phase == .idle)
      }
    }
    .sheet(isPresented: $showList) {
      WalkStopList(walk: walk) { i in
        showList = false
        Task {
          await walk.jump(to: i)
          follow()
        }
      }
      .presentationDetents([.medium, .large])
    }
    .errorAlert($error)
    .task { await begin() }
    .onChange(of: walk.location) { _, location in
      guard walk.navigator.isNavigating, following, let location else { return }
      withAnimation(.easeInOut(duration: 0.8)) {
        camera = WalkMapLayer.followCamera(at: location, heading: WalkMapLayer.heading(location: location, navigator: walk.navigator))
      }
    }
    .onChange(of: camera) { _, position in
      if position.positionedByUser, walk.navigator.isNavigating { withAnimation { following = false } }
    }
    .onChange(of: walk.phase) { _, phase in
      switch phase {
      case .arrived, .done: UINotificationFeedbackGenerator().notificationOccurred(.success)
      case .walking: follow()
      case .idle: break
      }
    }
    .onChange(of: walk.tracker.steps) {
      lastStepAt = Date()
      walk.refreshActivity()
    }
  }

  private func tint(_ i: Int) -> Color {
    if walk.visited.contains(i) || walk.skipped.contains(i) { return Color.lociMutedInk.opacity(0.5) }
    if (walk.phase == .walking && i == walk.index) || (walk.phase == .arrived && i == walk.upcoming) { return .lociCoral }
    return LociTheme.dayColor(1)
  }

  /// Reattach to this day's walk if it is already running; otherwise start it.
  private func begin() async {
    guard !walk.isWalking(key: day.id) else { return }
    do {
      let here = try await CurrentLocation.fetch()
      await walk.start(day, from: here)
    } catch CurrentLocation.Failure.denied {
      error = "Allow location in Settings to walk this day"
    } catch {
      self.error = error.userMessage
    }
  }

  private func follow() {
    withAnimation { following = true }
    guard let location = walk.location else {
      camera = .userLocation(followsHeading: true, fallback: .automatic)
      return
    }
    withAnimation(.easeInOut(duration: 0.8)) {
      camera = WalkMapLayer.followCamera(at: location, heading: WalkMapLayer.heading(location: location, navigator: walk.navigator))
    }
  }
}
