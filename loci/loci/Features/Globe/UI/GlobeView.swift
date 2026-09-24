import MapKit
import SwiftUI

/// Loads the globe once and keeps the drawn arcs, so the great circles are
/// computed per load rather than per frame. A failure never reads as an empty
/// history: with nothing on screen it is an error with a retry (web shows
/// none); a failed refresh is an alert and the globe stays.
@MainActor @Observable final class GlobeStore {
  enum Phase: Equatable {
    case idle, loading, loaded
    case failed(String)
  }

  /// One drawable piece of a leg's arc (a leg over the antimeridian has two).
  struct ArcPiece: Identifiable {
    let id: String
    let legID: String
    let coordinates: [CLLocationCoordinate2D]
  }

  private(set) var data = GlobeData.empty
  private(set) var phase = Phase.idle
  private(set) var arcs: [ArcPiece] = []
  var error: String?

  private let service: TravelHistoryService

  init(service: TravelHistoryService = ConnectTravelHistoryService()) { self.service = service }

  func loadIfNeeded() async { if phase == .idle { await load() } }

  func load() async {
    if data.isEmpty { phase = .loading }
    do {
      let loaded = try await service.globeData()
      data = loaded
      arcs = Self.pieces(loaded.legs)
      phase = .loaded
    } catch {
      guard !(error is CancellationError || (error as? APIError) == .cancelled) else {
        if phase == .loading { phase = .idle }
        return
      }
      if phase == .loaded, !data.isEmpty { self.error = error.userMessage } else { phase = .failed(error.userMessage) }
    }
  }

  func leg(_ id: String?) -> GlobeLeg? { id.flatMap { id in data.legs.first { $0.id == id } } }
  func city(_ id: String?) -> GlobeCity? { id.flatMap { id in data.cities.first { $0.id == id } } }

  static func pieces(_ legs: [GlobeLeg]) -> [ArcPiece] {
    legs.flatMap { leg in
      GreatCircle.segments(GreatCircle.path(from: leg.from, to: leg.to)).enumerated().map { index, piece in
        ArcPiece(id: "\(leg.id)~\(index)", legID: leg.id, coordinates: piece.map(\.coordinate))
      }
    }
  }
}

nonisolated extension GeoPoint { var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) } }

/// Where you've been (web: /globe). The cities you have actually been to on a
/// satellite globe, the legs between them as great circles, the numbers and
/// the legs in a sheet underneath. Tap a city for its visits and a way into
/// Recents; tap a leg to fly to it.
struct GlobeView: View {
  @State var store: GlobeStore
  @State private var camera: MapCameraPosition
  @State private var isGlobe = true
  @State private var selectedLegID: String?
  @State private var selectedCityID: String?
  @State private var showSheet = false
  @State private var detent = GlobeView.peek
  @State private var recentsCity: String?
  @State private var hasFramed = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  static let peek = PresentationDetent.fraction(0.3)
  /// Far enough out that MapKit draws the whole Earth as a globe.
  static let globeDistance: CLLocationDistance = 40_000_000

  private let recents: RecentsService

  init(store: GlobeStore = GlobeStore(), recents: RecentsService = ConnectRecentsService()) {
    _store = State(initialValue: store)
    self.recents = recents
    _camera = State(
      initialValue: .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 25, longitude: 10), distance: Self.globeDistance))
    )
  }

  private let arcColor = Color(hex: 0xFA7862)
  private let selectedArcColor = Color(hex: 0xFFD2C4)

  var body: some View {
    ZStack {
      // The map waits for the first load so it opens already facing your
      // travels: moving the camera after it appears leaves MapKit zoomed in
      // far closer than the same camera set up front.
      if hasFramed { map } else { Color.lociPaper.ignoresSafeArea() }
    }.overlay { stateOverlay }.toolbarColorScheme(hasFramed && isGlobe ? .dark : nil, for: .navigationBar).safeAreaInset(edge: .top) {
      if let city = store.city(selectedCityID) {
        CityCallout(city: city, onRecents: { openRecents(city) }, onClose: { selectedCityID = nil }).padding(.horizontal, 16).padding(.top, 8)
          .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
      }
    }.animation(reduceMotion ? nil : LociTheme.selectionSettle, value: selectedCityID).navigationTitle("Where you've been")
      .navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            isGlobe.toggle()
          } label: {
            Label(isGlobe ? "Flat map" : "Globe", systemImage: isGlobe ? "map" : "globe")
          }.accessibilityHint(isGlobe ? "Shows a flat map" : "Shows the globe")
        }
      }.sheet(isPresented: $showSheet) {
        LegsSheet(data: store.data, selectedLegID: selectedLegID) { select($0) }.presentationDetents(
          [Self.peek, .medium, .large],
          selection: $detent
        ).presentationBackgroundInteraction(.enabled(upThrough: .medium)).presentationDragIndicator(.visible).interactiveDismissDisabled()
      }.navigationDestination(item: $recentsCity) { RecentCityLink(cityName: $0, service: recents) }.task { await store.loadIfNeeded() }.onChange(
        of: store.phase
      ) { _, phase in
        syncSheet()
        if phase == .loaded, !hasFramed { frameTravels() }
      }.onChange(of: recentsCity) { syncSheet() }.onAppear {
        Analytics.screen("globe")
        syncSheet()
      }.onDisappear { showSheet = false }.errorAlert($store.error)
  }

  private var map: some View {
    Map(position: $camera) {
      ForEach(store.arcs) { piece in
        let selected = piece.legID == selectedLegID
        MapPolyline(coordinates: piece.coordinates).stroke(
          selected ? selectedArcColor : arcColor.opacity(selectedLegID == nil ? 0.9 : 0.45),
          style: StrokeStyle(lineWidth: selected ? 4 : 2, lineCap: .round)
        )
      }
      ForEach(store.data.cities) { city in
        Annotation(city.cityName, coordinate: city.point.coordinate, anchor: .center) {
          CityDot(city: city, isSelected: city.id == selectedCityID) { selectedCityID = city.id == selectedCityID ? nil : city.id }
        }
      }
      if let leg = store.leg(selectedLegID), !leg.label.isEmpty {
        Annotation("", coordinate: GreatCircle.midpoint(from: leg.from, to: leg.to).coordinate, anchor: .bottom) {
          Text(leg.label).font(.lociCaption(12).weight(.semibold)).monospacedDigit().foregroundStyle(Color(hex: 0xF5EDE1)).padding(.horizontal, 10)
            .padding(.vertical, 5).background(Color(hex: 0x1B2126), in: Capsule()).overlay(Capsule().strokeBorder(Color(hex: 0x3A444C))).padding(
              .bottom,
              6
            ).accessibilityLabel("Selected leg: \(leg.fromName) to \(leg.toName), \(leg.label)")
        }.annotationTitles(.hidden)
      }
    }.mapStyle(
      isGlobe ? .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll) : .standard(elevation: .flat, pointsOfInterest: .excludingAll)
    ).mapControls {
      MapCompass()
      MapScaleView()
    }.background(Color.black)
  }

  // MARK: - States

  @ViewBuilder private var stateOverlay: some View {
    switch store.phase {
    case .idle, .loading:
      ProgressView("Loading your travels…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius))
    case .failed(let message):
      ContentUnavailableView {
        Label("Could not load your travels", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("Try again") { Task { await store.load() } }.buttonStyle(.borderedProminent).tint(Color.lociForest)
      }.background(Color.lociPaper.opacity(0.94))
    case .loaded:
      if store.data.isEmpty {
        GlobeEmptyState(backfilled: store.data.backfilled) { Task { await store.load() } }.background(Color.lociPaper.opacity(0.94))
      }
    }
  }

  // MARK: - Actions

  /// The sheet shows only over a globe with something on it, and steps aside
  /// while Recents is pushed on top.
  private func syncSheet() { showSheet = store.phase == .loaded && !store.data.isEmpty && recentsCity == nil }

  private func select(_ leg: GlobeLeg?) {
    selectedLegID = leg?.id
    guard let leg else { return }
    selectedCityID = nil
    detent = Self.peek
    let span = max(leg.distanceKm, GreatCircle.distanceKm(leg.from, leg.to))
    let distance = min(max(span * 1000 * 2.6, 400_000), Self.globeDistance)
    move(to: MapCamera(centerCoordinate: GreatCircle.midpoint(from: leg.from, to: leg.to).coordinate, distance: distance))
  }

  /// Turns the globe to face the travels once, after the first load.
  private func frameTravels() {
    defer { hasFramed = true }
    guard let centre = GreatCircle.centroid(store.data.cities.map(\.point)) else { return }
    // Kept off the poles, so a world-wide history still shows the globe upright.
    let latitude = min(max(centre.latitude, -30), 30)
    camera = .camera(
      MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: latitude, longitude: centre.longitude), distance: Self.globeDistance)
    )
  }

  private func openRecents(_ city: GlobeCity) { recentsCity = city.cityName }

  /// No sweeping flight under Reduce Motion: the camera cuts.
  private func move(to target: MapCamera) {
    if reduceMotion { camera = .camera(target) } else { withAnimation(.easeInOut(duration: 0.9)) { camera = .camera(target) } }
  }
}

// MARK: - Pieces

/// A visited city: a slate dot sized by visits (web's palette on the dark globe).
private struct CityDot: View {
  let city: GlobeCity
  let isSelected: Bool
  let onTap: () -> Void

  var body: some View {
    let diameter = city.nodeRadius * 2
    Button(action: onTap) {
      Circle().fill(Color(hex: 0x8FA6B5)).overlay(
        Circle().strokeBorder(isSelected ? Color.white : Color(hex: 0x0E1114), lineWidth: isSelected ? 3 : 1.5)
      ).frame(width: diameter, height: diameter).frame(width: 44, height: 44).contentShape(Circle())
    }.buttonStyle(.plain).accessibilityLabel("\(city.cityName), \(GlobeCallout.visits(city.visitCount))").accessibilityAddTraits(
      isSelected ? .isSelected : []
    )
  }
}

/// Copy shared by the callout and the dots.
enum GlobeCallout { static func visits(_ count: Int) -> String { count == 1 ? "1 visit" : "\(count) visits" } }

/// A tapped city: visits, last visit, and the way into its Recents page.
/// Web wires `onSelectNode` to nothing; this is new on iOS.
private struct CityCallout: View {
  let city: GlobeCity
  let onRecents: () -> Void
  let onClose: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(city.cityName).font(.lociTitle(20)).foregroundStyle(Color.lociInk)
        Text(subtitle).font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
        Button(action: onRecents) { Label("See in Recents", systemImage: "clock.arrow.circlepath").font(.lociCaption(13).weight(.semibold)) }
          .buttonStyle(.bordered).tint(Color.lociForest).padding(.top, 4)
      }
      Spacer(minLength: 0)
      Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).frame(width: 44, height: 44) }.buttonStyle(
        .plain
      ).foregroundStyle(Color.lociMutedInk).accessibilityLabel("Close").padding(.top, -12).padding(.trailing, -12)
    }.padding(16).background(Color.lociCard, in: RoundedRectangle(cornerRadius: LociTheme.cornerRadiusHero)).overlay(
      RoundedRectangle(cornerRadius: LociTheme.cornerRadiusHero).strokeBorder(Color.lociBorder, lineWidth: LociTheme.borderWidth)
    ).shadow(color: .black.opacity(0.18), radius: 12, y: 4)
  }

  private var subtitle: String {
    var parts = [GlobeCallout.visits(city.visitCount)]
    if let last = city.lastVisitAt { parts.append("last \(last.formatted(date: .abbreviated, time: .omitted))") }
    if !city.country.isEmpty { parts.insert(city.country, at: 0) }
    return parts.joined(separator: " · ")
  }
}

/// Nothing to draw (web copy). Backfilled: really nowhere yet. Not
/// backfilled: the server has not worked it out (or the backfill failed), so
/// a retry is worth offering.
private struct GlobeEmptyState: View {
  let backfilled: Bool
  let onRetry: () -> Void

  var body: some View {
    if backfilled {
      ContentUnavailableView(
        "No travels recorded yet",
        systemImage: "globe.europe.africa",
        description: Text("Cities appear here once a trip has real dates in the past, or once you mark a stop as visited. We don't guess from plans.")
      )
    } else {
      ContentUnavailableView {
        Label("Not worked out yet", systemImage: "hourglass")
      } description: {
        Text("We haven't worked out your travel history yet. Check back shortly.")
      } actions: {
        Button("Check again", action: onRetry).buttonStyle(.bordered).tint(Color.lociForest)
      }
    }
  }
}

/// "See in Recents" for one city: Recents' Cities list, matched by name.
/// Recents only knows cities you asked about, which is not the same set as
/// cities you went to, so a miss says so and offers the whole list.
struct RecentCityLink: View {
  let cityName: String
  var service: RecentsService = ConnectRecentsService()
  @State private var city: RecentCity?
  @State private var phase = GlobeStore.Phase.idle

  var body: some View {
    if let city {
      RecentCityView(city: city)
    } else {
      placeholder.background(Color.lociPaper.ignoresSafeArea()).navigationTitle(cityName).task { if phase == .idle { await load() } }
    }
  }

  @ViewBuilder private var placeholder: some View {
    switch phase {
    case .idle, .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let message):
      ContentUnavailableView {
        Label("Could not load Recents", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("Try again") { Task { await load() } }.buttonStyle(.borderedProminent).tint(Color.lociForest)
      }
    case .loaded:
      ContentUnavailableView {
        Label("Nothing in Recents for \(cityName)", systemImage: "clock.arrow.circlepath")
      } description: {
        Text("Recents lists the cities you asked Loci about. You haven't asked about this one.")
      } actions: {
        NavigationLink("Open Recents") { RecentsView(segment: .cities) }.buttonStyle(.bordered).tint(Color.lociForest)
      }
    }
  }

  private func load() async {
    phase = .loading
    do {
      let cities = try await service.cities(userId: AuthSessionManager.shared.currentUserID ?? "me")
      city = RecentCityMatch.find(cityName, in: cities)
      phase = .loaded
    } catch { phase = .failed(error.userMessage) }
  }
}

/// The Recents city for a visited city's name: case- and accent-insensitive.
nonisolated enum RecentCityMatch {
  static func find(_ name: String, in cities: [RecentCity]) -> RecentCity? {
    let key = name.trimmingCharacters(in: .whitespaces)
    guard !key.isEmpty else { return nil }
    return cities.first { $0.name.compare(key, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
  }
}
