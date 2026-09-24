import CoreLocation
import LociConnectProto
import MapKit
import SwiftUI

/// Everything the map draws for a result: numbered day-coloured pins, one
/// dashed route per day in itinerary order, extras in the ungrouped colour,
/// and a halo for every local alert that carries a coordinate.
struct ResultsMapData: Equatable {
  struct Pin: Equatable, Identifiable {
    let id: String
    let name: String
    let index: Int
    let day: Int?
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: Pin, rhs: Pin) -> Bool { lhs.id == rhs.id && lhs.index == rhs.index && lhs.day == rhs.day }
  }

  struct Route: Equatable {
    let day: Int
    let coordinates: [CLLocationCoordinate2D]

    static func == (lhs: Route, rhs: Route) -> Bool { lhs.day == rhs.day && lhs.coordinates.count == rhs.coordinates.count }
  }

  struct Halo: Equatable {
    let title: String
    let severity: Double
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: Halo, rhs: Halo) -> Bool { lhs.title == rhs.title && lhs.severity == rhs.severity }
  }

  var pins: [Pin] = []
  var routes: [Route] = []
  var halos: [Halo] = []
  var dayNumbers: [Int] = []

  var isEmpty: Bool { pins.isEmpty }

  init(groups: [DayGroup], extras: [Loci_Poi_POIDetailedInfo], sequence: [String: Int], showsDays: Bool, alerts: [Loci_Localcontext_LocalAlert]) {
    var next = sequence.values.max() ?? 0
    for group in groups {
      var route: [CLLocationCoordinate2D] = []
      for stop in group.stops where GoogleMapsRoute.hasCoordinate(stop) {
        let coordinate = CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)
        let index = sequence[stop.stableID] ?? 0
        // A list without days is "day 0" on web: one colour, still numbered.
        pins.append(Pin(id: stop.stableID, name: stop.name, index: index, day: showsDays ? group.number : 0, coordinate: coordinate))
        route.append(coordinate)
      }
      if showsDays {
        dayNumbers.append(group.number)
        if route.count > 1 { routes.append(Route(day: group.number, coordinates: route)) }
      }
    }
    for stop in extras where GoogleMapsRoute.hasCoordinate(stop) {
      next += 1
      let coordinate = CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)
      pins.append(Pin(id: stop.stableID, name: stop.name, index: next, day: nil, coordinate: coordinate))
    }
    halos = alerts.filter { $0.hasLatitude && $0.hasLongitude }.map {
      Halo(title: $0.title, severity: $0.severity, coordinate: .init(latitude: $0.latitude, longitude: $0.longitude))
    }
  }

  static func color(day: Int?) -> Color { day.map(LociTheme.dayColor) ?? LociTheme.ungroupedColor }

  /// Where the full map opens: Day 1's first stop, else the first pin at all.
  var flyoverStart: Pin? { pins.first(where: { $0.day == 1 }) ?? pins.first }

  /// A pitched street-level camera over one place, so MapKit's 3D buildings
  /// and landmarks read as 3D. Used for the opening flyover and for selection.
  static func flyoverCamera(at coordinate: CLLocationCoordinate2D) -> MapCamera {
    MapCamera(centerCoordinate: coordinate, distance: flyoverDistance, heading: flyoverHeading, pitch: flyoverPitch)
  }

  static let flyoverDistance: Double = 900
  static let flyoverPitch: Double = 60
  static let flyoverHeading: Double = 30
}

/// The map content itself, shared by the hero card and the full map.
struct ResultsMapContent: MapContent {
  let data: ResultsMapData
  var selectedID: String?

  var body: some MapContent {
    ForEach(data.routes, id: \.day) { route in
      MapPolyline(coordinates: route.coordinates)
        .stroke(ResultsMapData.color(day: route.day), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 5]))
    }
    ForEach(data.halos, id: \.title) { halo in
      MapCircle(center: halo.coordinate, radius: 400)
        .foregroundStyle(LocalAlertStyle.color(severity: halo.severity).opacity(0.18))
        .stroke(LocalAlertStyle.color(severity: halo.severity), lineWidth: 1)
    }
    ForEach(data.pins) { pin in
      Annotation(pin.name, coordinate: pin.coordinate, anchor: .center) {
        MapPin(number: pin.index, color: ResultsMapData.color(day: pin.day), isSelected: pin.id == selectedID)
      }
      .annotationTitles(.hidden)
      .tag(pin.id)
    }
  }
}

struct MapPin: View {
  let number: Int
  let color: Color
  var isSelected = false

  var body: some View {
    Text("\(number)")
      .font(.lociCoord(isSelected ? 13 : 11)).foregroundStyle(LociTheme.stampInk)
      .frame(width: isSelected ? 32 : 26, height: isSelected ? 32 : 26)
      .background(color, in: Circle())
      .overlay(Circle().stroke(LociTheme.stampInk, lineWidth: 2))
      .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
      .animation(LociTheme.selectionSettle, value: isSelected)
      .accessibilityLabel("Stop \(number)")
  }
}

/// The 260-point map hero under the summary. Not interactive itself: any tap
/// opens the full map (the layout rule for Discover results).
struct ResultsMapCard: View {
  let data: ResultsMapData
  let selectedID: String?
  var onExpand: () -> Void

  @State private var camera: MapCameraPosition = .automatic

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Map(position: $camera, interactionModes: []) {
        ResultsMapContent(data: data, selectedID: selectedID)
      }
      .mapStyle(.standard(pointsOfInterest: .excludingAll))
      .mapControlVisibility(.hidden)
      .frame(height: 260)
      .clipShape(RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
      .overlay(alignment: .bottomTrailing) {
        Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
          .font(.lociCaption(12)).foregroundStyle(Color.lociInk)
          .padding(.horizontal, 10).padding(.vertical, 6)
          .background(.thinMaterial, in: Capsule())
          .padding(10)
      }
      .contentShape(Rectangle())
      .onTapGesture(perform: onExpand)
      .onChange(of: data) { _, _ in camera = .automatic }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Map of \(data.pins.count) places")
      .accessibilityAddTraits(.isButton)
      .accessibilityHint("Opens the full map")
      if data.dayNumbers.count > 1 { MapLegend(days: data.dayNumbers) }
    }
  }
}

struct MapLegend: View {
  let days: [Int]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(days, id: \.self) { day in
          HStack(spacing: 4) {
            Circle().fill(LociTheme.dayColor(day)).frame(width: 8, height: 8)
            Text("Day \(day)").lociCoordStyle(10).fixedSize()
          }
        }
      }
    }
    .scrollClipDisabled()
  }
}

/// Full-screen map with the stops in a detent sheet; selection syncs both
/// ways (Nearby's shape, per the layout rule).
struct FullMapView: View {
  let data: ResultsMapData
  let groups: [DayGroup]
  let sequence: [String: Int]
  let destination: SearchDestination
  let showsDays: Bool
  let title: String
  @Binding var selectedID: String?

  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var camera: MapCameraPosition = .automatic
  @State private var showList = true
  @State private var detail: Loci_Poi_POIDetailedInfo?

  var body: some View {
    NavigationStack {
      Map(position: $camera, selection: $selectedID) {
        ResultsMapContent(data: data, selectedID: selectedID)
      }
      .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
      .mapControls { MapCompass(); MapPitchToggle(); MapScaleView() }
      .ignoresSafeArea(edges: .bottom)
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
      .sensoryFeedback(.selection, trigger: selectedID)
      .onAppear {
        guard let start = data.flyoverStart else { return }
        withAnimation(reduceMotion ? nil : LociTheme.resultArrive) {
          camera = .camera(ResultsMapData.flyoverCamera(at: start.coordinate))
        }
      }
      .onChange(of: selectedID) { _, id in
        guard let id, let pin = data.pins.first(where: { $0.id == id }) else { return }
        withAnimation(reduceMotion ? nil : LociTheme.selectionSettle) {
          camera = .camera(ResultsMapData.flyoverCamera(at: pin.coordinate))
        }
      }
      .sheet(isPresented: $showList) {
        MapStopList(groups: groups, sequence: sequence, destination: destination, showsDays: showsDays, selectedID: $selectedID) { detail = $0 }
          .presentationDetents([.fraction(0.25), .medium, .large])
          .presentationBackgroundInteraction(.enabled(upThrough: .medium))
          .interactiveDismissDisabled()
          .sheet(item: $detail) { stop in PlaceDetailSheet(stop: stop, destination: destination, cityName: title) }
      }
    }
  }
}

/// The list under the full map: one row per stop, days as section headers.
private struct MapStopList: View {
  let groups: [DayGroup]
  let sequence: [String: Int]
  let destination: SearchDestination
  let showsDays: Bool
  @Binding var selectedID: String?
  var onDetail: (Loci_Poi_POIDetailedInfo) -> Void

  var body: some View {
    ScrollViewReader { proxy in
      List {
        ForEach(groups, id: \.number) { group in
          Section {
            ForEach(group.stops, id: \.stableID) { stop in
              Button { selectedID = stop.stableID } label: { row(stop, day: group.number) }
                .listRowBackground(selectedID == stop.stableID ? Color.lociSage : Color.lociCard)
                .swipeActions(edge: .trailing) { Button("Details", systemImage: "info.circle") { onDetail(stop) }.tint(.lociForest) }
                .id(stop.stableID)
            }
          } header: {
            if showsDays { Text("Day \(group.number)").lociCoordStyle(10) }
          }
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

  private func row(_ stop: Loci_Poi_POIDetailedInfo, day: Int) -> some View {
    HStack(spacing: 10) {
      MapPin(number: sequence[stop.stableID] ?? 0, color: showsDays ? LociTheme.dayColor(day) : LociTheme.listColor)
      VStack(alignment: .leading, spacing: 2) {
        Text(stop.name).font(.lociHeadline(15)).foregroundStyle(Color.lociInk).lineLimit(1)
        if let meta = StopMeta.line(for: stop, destination: destination) ?? (stop.category.isEmpty ? nil : stop.category) {
          Text(meta).font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk).lineLimit(1)
        }
      }
      Spacer()
      Button("Details", systemImage: "info.circle") { onDetail(stop) }.labelStyle(.iconOnly).foregroundStyle(Color.lociForest)
    }
  }
}
