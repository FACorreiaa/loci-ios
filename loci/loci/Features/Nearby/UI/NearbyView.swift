import CoreLocation
import LociConnectProto
import MapKit
import SwiftUI

/// Near me (web: /nearme; /near redirects there, and there is no /nearby).
/// Map first, list in a sheet (NATIVE_DESIGN: "Nearby opens with the map by
/// default, with a sheet for the list"). The search is web's exactly:
/// StreamChat{message: "Find places near me within N kilometers…",
/// cityName: "nearme", userLocation}.
struct NearbyView: View {
  static let radii = [5, 10, 25, 50]

  /// web: routes/nearme/index.tsx `searchNearby`
  static func message(radiusKm: Int, coordinate: CLLocationCoordinate2D) -> String {
    let lat = String(format: "%.6f", coordinate.latitude)
    let lon = String(format: "%.6f", coordinate.longitude)
    return "Find places near me within \(radiusKm) kilometers. My location is at latitude \(lat) and longitude \(lon). "
      + "Show me restaurants, attractions, hotels, and activities nearby."
  }

  private let controller = SearchSessionController.shared
  @State private var coordinate: CLLocationCoordinate2D?
  @State private var radiusKm = 50
  @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
  @State private var selectedID: String?
  @State private var showList = true
  @State private var sessionId: String?
  @State private var error: String?
  @State private var detent: PresentationDetent = .medium
  /// The camera rides behind the walker until the person pans the map.
  @State private var following = true
  @State private var lastStepAt = Date.distantPast
  private let walk = NearbyWalk.shared
  private var navigator: WalkNavigator { walk.navigator }

  /// Only this screen's search, not whatever else is running.
  private var places: [Loci_Poi_POIDetailedInfo] {
    guard let sessionId, controller.state.sessionId == sessionId else { return [] }
    return controller.state.allPlaces.filter { $0.hasLatitude && $0.hasLongitude }
  }

  private var isSearching: Bool { controller.state.isActive && (sessionId == nil || controller.state.sessionId == sessionId) }

  /// Where the walk starts from: the live fix while walking, else the search's.
  private var here: CLLocationCoordinate2D? { walk.location?.coordinate ?? coordinate }

  private var walkerHeading: CLLocationDirection? {
    guard let location = walk.location else { return nil }
    return WalkingRoute.heading(
      course: location.course,
      speed: location.speed,
      from: location.coordinate,
      toward: navigator.remaining.dropFirst().first ?? navigator.destinationCoordinate
    )
  }

  /// Moving by GPS, or the pedometer counted a step in the last few seconds.
  private var isMoving: Bool {
    (walk.location?.speed ?? 0) > 0.3 || Date().timeIntervalSince(lastStepAt) < 3
  }

  var body: some View {
    Map(position: $camera, selection: $selectedID) {
      if navigator.isNavigating, let location = walk.location {
        Annotation("You", coordinate: location.coordinate, anchor: .bottom) {
          WalkerFigure(
            facesLeft: walkerHeading.map(WalkingRoute.facesLeft) ?? false,
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
      ForEach(places, id: \.stableID) { poi in
        Marker(
          poi.name,
          systemImage: PlaceSymbol.name(for: poi.category),
          coordinate: CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
        )
          .tint(LociTheme.dayColor(Int(poi.hasDay ? poi.day : 1)))
          .tag(poi.stableID)
      }
    }
    .mapControls {
      MapUserLocationButton()
      MapCompass()
    }
    .overlay(alignment: .top) {
      if navigator.isNavigating, !following {
        Button("Recenter", systemImage: "location.north.line.fill") { follow() }
          .lociProminentButton()
          .padding(.top, 8)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .onChange(of: selectedID) { _, id in
      guard let id else {
        if !navigator.isNavigating { navigator.end() }
        return
      }
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      showList = true
      guard let poi = places.first(where: { $0.stableID == id }), let here else { return }
      Task {
        await navigator.preview(to: poi, from: here)
        guard navigator.destination?.stableID == id, let rect = WalkingRoute.mapRect(for: navigator.remaining) else { return }
        withAnimation(LociTheme.selectionSettle) { camera = .rect(rect) }
      }
    }
    .onChange(of: walk.location) { _, location in
      guard navigator.isNavigating, following, let location else { return }
      withAnimation(.easeInOut(duration: 0.8)) { camera = followCamera(at: location) }
    }
    .onChange(of: camera) { _, position in
      if position.positionedByUser, navigator.isNavigating { withAnimation { following = false } }
    }
    .onChange(of: navigator.arrivedAt) { _, arrived in
      guard arrived != nil else { return }
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      detent = .medium
      withAnimation { camera = .userLocation(fallback: .automatic) }
    }
    .navigationTitle("Near me")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Picker("Radius", selection: $radiusKm) { ForEach(Self.radii, id: \.self) { Text("\($0) km").tag($0) } }
        } label: {
          Label("\(radiusKm) km", systemImage: "scope")
        }
      }
    }
    .onChange(of: radiusKm) { Task { await search() } }
    .sheet(isPresented: $showList) {
      VStack(spacing: 0) {
        if navigator.destination != nil || navigator.arrivedAt != nil {
          RouteCard(
            navigator: navigator,
            steps: walk.isActive && !walk.tracker.deniedByUser ? walk.tracker.stepsText : nil,
            canGo: here != nil,
            onGo: go,
            onEnd: endRoute
          )
          .padding(.top, 18)
        }
        NearbyList(places: places, selectedID: $selectedID, isSearching: isSearching, walk: walk, radiusKm: radiusKm) {
          Task { await search() }
        }
      }
        .background(Color.lociPaper)
        .presentationDetents([.fraction(0.25), .medium, .large], selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }
    .errorAlert($error)
    .task { if sessionId == nil { await search() } }
    .onChange(of: controller.startedLink) { _, link in
      if isSearching, sessionId == nil { sessionId = link?.sessionId }
    }
    .onChange(of: places.map(\.stableID)) { Task { await walk.update(places: places) } }
    .onChange(of: walk.tracker.steps) {
      lastStepAt = Date()
      walk.refreshActivity()
    }
  }

  private func go() {
    Task {
      await walk.navigate(places: places, radiusKm: radiusKm)
      detent = .fraction(0.25)
      follow()
    }
  }

  private func endRoute() {
    navigator.end()
    selectedID = nil
    following = true
    withAnimation { camera = .userLocation(fallback: .automatic) }
  }

  private func follow() {
    withAnimation { following = true }
    guard let location = walk.location else {
      camera = .userLocation(followsHeading: true, fallback: .automatic)
      return
    }
    withAnimation(.easeInOut(duration: 0.8)) { camera = followCamera(at: location) }
  }

  /// Low and tilted behind the walker, looking the way they are heading.
  private func followCamera(at location: CLLocation) -> MapCameraPosition {
    .camera(MapCamera(centerCoordinate: location.coordinate, distance: 400, heading: walkerHeading ?? 0, pitch: 60))
  }

  private func search() async {
    do {
      var here = coordinate
      if here == nil { here = try await CurrentLocation.fetch() }
      guard let here else { return }
      coordinate = here
      sessionId = nil
      try await controller.start(
        query: Self.message(radiusKm: radiusKm, coordinate: here),
        cityName: "nearme",
        latitude: here.latitude,
        longitude: here.longitude,
        useDefaultProfile: false
      )
    } catch { self.error = error.userMessage }
  }
}

/// The sheet under the map.
struct NearbyList: View {
  let places: [Loci_Poi_POIDetailedInfo]
  @Binding var selectedID: String?
  let isSearching: Bool
  let walk: NearbyWalk
  let radiusKm: Int
  let onRetry: () -> Void

  var body: some View {
    ScrollViewReader { proxy in
      List {
        WalkRow(walk: walk, places: places, radiusKm: radiusKm)
        if isSearching, places.isEmpty {
          HStack {
            ProgressView()
            Text("Looking around you…").foregroundStyle(Color.lociMutedInk)
          }
        } else if places.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("Nothing found nearby.")
            Text("Try expanding your search radius.").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
            Button("Search again", action: onRetry)
          }
        }
        ForEach(places, id: \.stableID) { poi in
          Button {
            selectedID = poi.stableID
          } label: {
            VStack(alignment: .leading, spacing: 3) {
              HStack {
                Text(poi.name).font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
                Spacer()
                if poi.distance > 0 { Text(String(format: "%.1f km", poi.distance)).lociCoordStyle(10) }
              }
              if !poi.category.isEmpty { Text(poi.category).lociCoordStyle(10) }
              if !poi.descriptionPoi.isEmpty || !poi.description_p.isEmpty {
                Text(poi.descriptionPoi.isEmpty ? poi.description_p : poi.descriptionPoi)
                  .font(.lociCaption()).foregroundStyle(Color.lociMutedInk).lineLimit(2)
              }
            }
          }
          .listRowBackground(selectedID == poi.stableID ? Color.lociSage : Color.lociCard)
          .id(poi.stableID)
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .background(Color.lociPaper)
      .onChange(of: selectedID) { _, id in
        guard let id else { return }
        withAnimation(LociTheme.selectionSettle) { proxy.scrollTo(id, anchor: .top) }
      }
    }
  }
}

/// Start/stop the walk, with live steps and distance while it runs.
/// Motion & Fitness is asked on the first start; Live Activities need no prompt.
struct WalkRow: View {
  let walk: NearbyWalk
  let places: [Loci_Poi_POIDetailedInfo]
  let radiusKm: Int

  var body: some View {
    HStack(spacing: 12) {
      if walk.isActive {
        VStack(alignment: .leading, spacing: 2) {
          Text(walk.tracker.stepsText).font(.lociHeadline(16)).foregroundStyle(Color.lociInk).contentTransition(.numericText())
          Text(walk.tracker.deniedByUser ? "Steps off: allow Motion & Fitness in Settings" : "\(walk.tracker.distanceText) · \(places.count) places fenced")
            .lociCoordStyle(10)
        }
        Spacer()
        Button("Stop", systemImage: "stop.fill") { Task { await walk.stop() } }
          .buttonStyle(.bordered).tint(.lociCoral)
      } else {
        VStack(alignment: .leading, spacing: 2) {
          Text("Walk it").font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
          Text("Count steps and get a nudge when you pass a place").lociCoordStyle(10)
        }
        Spacer()
        Button("Start", systemImage: "figure.walk") { Task { await walk.start(places: places, radiusKm: radiusKm) } }
          .lociProminentButton()
          .disabled(places.isEmpty)
      }
    }
    .listRowBackground(Color.lociSage.opacity(0.35))
  }
}
