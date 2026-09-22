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

  /// Only this screen's search, not whatever else is running.
  private var places: [Loci_Poi_POIDetailedInfo] {
    guard let sessionId, controller.state.sessionId == sessionId else { return [] }
    return controller.state.allPlaces.filter { $0.hasLatitude && $0.hasLongitude }
  }

  private var isSearching: Bool { controller.state.isActive && (sessionId == nil || controller.state.sessionId == sessionId) }

  var body: some View {
    Map(position: $camera, selection: $selectedID) {
      UserAnnotation()
      ForEach(places, id: \.stableID) { poi in
        Marker(
          poi.name,
          systemImage: Self.symbol(for: poi.category),
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
    .onChange(of: selectedID) { _, id in
      guard id != nil else { return }
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      showList = true
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
      NearbyList(places: places, selectedID: $selectedID, isSearching: isSearching, onRetry: { Task { await search() } })
        .presentationDetents([.fraction(0.25), .medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }
    .errorAlert($error)
    .task { if sessionId == nil { await search() } }
    .onChange(of: controller.startedLink) { _, link in
      if isSearching, sessionId == nil { sessionId = link?.sessionId }
    }
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

  static func symbol(for category: String) -> String {
    switch category.lowercased() {
    case let c where c.contains("restaurant") || c.contains("food") || c.contains("cafe"): "fork.knife"
    case let c where c.contains("hotel") || c.contains("accommodation"): "bed.double"
    case let c where c.contains("museum"): "building.columns"
    case let c where c.contains("park") || c.contains("nature"): "tree"
    case let c where c.contains("bar") || c.contains("night"): "wineglass"
    default: "mappin"
    }
  }
}

/// The sheet under the map.
struct NearbyList: View {
  let places: [Loci_Poi_POIDetailedInfo]
  @Binding var selectedID: String?
  let isSearching: Bool
  let onRetry: () -> Void

  var body: some View {
    ScrollViewReader { proxy in
      List {
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
