import CoreLocation
import LociConnectProto
import SwiftUI

/// What a stop on an itinerary page offers besides opening it. The links are
/// there for everyone; the edits only for the trip's owner.
struct StopMenu {
  struct MoveTarget: Identifiable {
    let id: String
    let label: String
    let action: () -> Void
  }

  var googleURL: URL?
  var onGoogle: () -> Void = {}
  var onEatNearby: (() -> Void)?
  var onMoveUp: (() -> Void)?
  var onMoveDown: (() -> Void)?
  var moveTargets: [MoveTarget] = []
  var onRemove: (() -> Void)?

  /// The same items for the visible menu and the long-press menu.
  @MainActor @ViewBuilder func items(openURL: OpenURLAction) -> some View {
    if let googleURL {
      Button("Check on Google Maps", systemImage: "arrow.up.right.square") {
        onGoogle()
        openURL(googleURL)
      }
    }
    if let onEatNearby { Button("Eat nearby", systemImage: "fork.knife", action: onEatNearby) }
    if onMoveUp != nil || onMoveDown != nil || !moveTargets.isEmpty { Divider() }
    if let onMoveUp { Button("Move up", systemImage: "arrow.up", action: onMoveUp) }
    if let onMoveDown { Button("Move down", systemImage: "arrow.down", action: onMoveDown) }
    if !moveTargets.isEmpty {
      Menu("Move to…", systemImage: "calendar") {
        ForEach(moveTargets) { target in Button(target.label, action: target.action) }
      }
    }
    if let onRemove {
      Divider()
      Button("Remove from trip", systemImage: "trash", role: .destructive, action: onRemove)
    }
  }
}

/// Nearby places Loci has stored, by category. One query, no model.
nonisolated enum NearbyPlacesAPI {
  static func places(around coordinate: CLLocationCoordinate2D, radiusKm: Double, categories: [String] = []) async throws -> [Loci_Poi_POIDetailedInfo] {
    var request = Loci_Poi_SearchPOIRequest()
    request.latitude = coordinate.latitude
    request.longitude = coordinate.longitude
    request.radiusKm = radiusKm
    request.searchTags = categories
    let sent = request
    return try await rpc("Couldn't look around that stop.", sent) {
      await Loci_Poi_PoiserviceClient(client: ConnectTransport.shared.protocolClient).searchPoi(request: $0, headers: [:])
    }.pois
  }
}

/// Places to eat around one stop. Always ends with the same search on Google
/// Maps: Loci's list is what it has stored, not everything that is there.
struct EatNearbySheet: View {
  let anchor: Loci_Poi_POIDetailedInfo
  let cityName: String
  let onTrip: [Loci_Poi_POIDetailedInfo]
  /// nil when the viewer cannot add to this trip.
  var onAdd: ((Loci_Poi_POIDetailedInfo) async -> Bool)?

  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @State private var options: [EatNearby.Option] = []
  @State private var isLoading = true
  @State private var failed = false
  @State private var adding: String?
  @State private var added: Set<String> = []

  var body: some View {
    NavigationStack {
      List {
        Section {
          if isLoading {
            ProgressView().frame(maxWidth: .infinity)
          } else if failed {
            Text("Couldn't look around \(anchor.name). Try again in a moment.").foregroundStyle(Color.lociMutedInk)
          } else if !GoogleMapsRoute.hasCoordinate(anchor) {
            Text("Loci doesn't know exactly where \(anchor.name) is, so it can't look around it.").foregroundStyle(Color.lociMutedInk)
          } else {
            ForEach(options) { option in row(option) }
          }
        } header: {
          if !isLoading, !failed, GoogleMapsRoute.hasCoordinate(anchor) {
            Text(EatNearby.summary(count: options.count, stopName: anchor.name)).textCase(nil)
          }
        }
        if let google = EatNearby.googleURL(stopName: anchor.name, city: cityName) {
          Section {
            Button("See restaurants on Google Maps", systemImage: "arrow.up.right.square") { openURL(google) }
          } footer: {
            Text("Reviews, photos and opening hours are on Google Maps.")
          }
        }
      }
      .navigationTitle("Eat near \(anchor.name)").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
      .task { await load() }
    }
    .presentationDetents([.medium, .large])
  }

  private func row(_ option: EatNearby.Option) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(option.place.name).foregroundStyle(Color.lociInk)
        Text(meta(option)).lociCoordStyle(10)
      }
      Spacer(minLength: 8)
      if let google = GoogleMapsRoute.placeURL(name: option.place.name, city: cityName) {
        Button("Check \(option.place.name) on Google Maps", systemImage: "arrow.up.right.square") { openURL(google) }
          .labelStyle(.iconOnly).buttonStyle(.borderless)
      }
      if let onAdd {
        if added.contains(option.id) {
          Label("Added", systemImage: "checkmark").labelStyle(.iconOnly).foregroundStyle(Color.lociForest)
        } else {
          Button("Add after") {
            adding = option.id
            Task {
              if await onAdd(option.place) { added.insert(option.id) }
              adding = nil
            }
          }
          .buttonStyle(.bordered).tint(Color.lociForest).disabled(adding != nil)
          .accessibilityLabel("Add \(option.place.name) after \(anchor.name)")
        }
      }
    }
  }

  private func meta(_ option: EatNearby.Option) -> String {
    var parts = ["\(option.walkMinutes) min walk"]
    if !option.place.category.isEmpty { parts.append(option.place.category) }
    if option.place.rating > 0 { parts.append(option.place.rating.formatted(.number.precision(.fractionLength(1)))) }
    return parts.joined(separator: " · ")
  }

  private func load() async {
    defer { isLoading = false }
    guard GoogleMapsRoute.hasCoordinate(anchor) else {
      Analytics.capture(.eatNearbyOpened, ["result_count": 0, "has_coords": false])
      return
    }
    let coordinate = CLLocationCoordinate2D(latitude: anchor.latitude, longitude: anchor.longitude)
    do {
      let places = try await NearbyPlacesAPI.places(around: coordinate, radiusKm: EatNearby.radiusKm, categories: EatNearby.categories)
      options = EatNearby.options(around: coordinate, places: places, onTrip: onTrip + [anchor])
      Analytics.capture(.eatNearbyOpened, ["result_count": options.count, "has_coords": true])
    } catch {
      failed = true
    }
  }
}

/// Adds places from a pasted link (a Google Maps pin, a post, a video) to one
/// day. A place Loci knows goes in by its id; any other by name and pin.
struct PasteLinkSheet: View {
  let cityName: String
  let dayNumber: Int
  var service: any LinkImportService = ConnectLinkImportService()
  let onAdd: (ImportedPlace) async -> Bool

  @Environment(\.dismiss) private var dismiss
  @State private var url = ""
  @State private var places: [ImportedPlace] = []
  @State private var isReading = false
  @State private var message: String?
  @State private var added: Set<String> = []
  @State private var adding: String?

  var body: some View {
    NavigationStack {
      List {
        Section {
          TextField("Paste a link", text: $url)
            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            .submitLabel(.go).onSubmit { Task { await read() } }
          Button(isReading ? "Reading…" : "Find places") { Task { await read() } }
            .disabled(isReading || url.trimmingCharacters(in: .whitespaces).isEmpty)
        } footer: {
          Text(message ?? "A Google Maps pin, or a post, video or article that names places.")
        }
        if !places.isEmpty {
          Section("Add to day \(dayNumber)") {
            ForEach(places) { place in
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(place.savedAs ?? place.name).foregroundStyle(Color.lociInk)
                  if let address = place.address { Text(address).lociCoordStyle(10).lineLimit(1) }
                }
                Spacer(minLength: 8)
                if added.contains(place.id) {
                  Label("Added", systemImage: "checkmark").labelStyle(.iconOnly).foregroundStyle(Color.lociForest)
                } else {
                  Button("Add") {
                    adding = place.id
                    Task {
                      if await onAdd(place) { added.insert(place.id) }
                      adding = nil
                    }
                  }
                  .buttonStyle(.bordered).tint(Color.lociForest).disabled(adding != nil)
                  .accessibilityLabel("Add \(place.name) to day \(dayNumber)")
                }
              }
            }
          }
        }
      }
      .navigationTitle("Add from a link").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }
  }

  private func read() async {
    guard let link = LinkImportLink.normalized(url) else {
      message = "Paste a public link to a post, video, map pin or article."
      return
    }
    isReading = true
    defer { isReading = false }
    message = nil
    do {
      let found = try await service.importPlaces(url: link, cityHint: cityName)
      places = found.places
      if places.isEmpty { message = "No places found in that link." }
    } catch {
      message = LinkImportStore.message(for: error)
    }
  }
}

nonisolated extension TripEdits {
  /// A stop for a place read from a link.
  static func stop(from place: ImportedPlace) -> Loci_Trip_TripStop {
    var stop = Loci_Trip_TripStop()
    stop.id = UUID().uuidString.lowercased()
    let name = (place.poiName ?? place.name).trimmingCharacters(in: .whitespacesAndNewlines)
    stop.name = String((name.isEmpty ? TripStopBuilder.fallbackName : name).prefix(TripStopBuilder.nameLimit))
    if let id = place.poiID, SavedPlace.isStoredID(id) { stop.poiID = id }
    if !place.note.isEmpty { stop.notes = String(place.note.prefix(TripStopBuilder.notesLimit)) }
    if let latitude = place.latitude, let longitude = place.longitude, latitude != 0 || longitude != 0 {
      stop.latitude = latitude
      stop.longitude = longitude
    }
    if let address = place.address { stop.address = address }
    return stop
  }

  /// A stop that is only a name: what the traveller typed, when Loci has no
  /// such place.
  static func stop(named name: String) -> Loci_Trip_TripStop {
    var stop = Loci_Trip_TripStop()
    stop.id = UUID().uuidString.lowercased()
    stop.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(TripStopBuilder.nameLimit))
    return stop
  }
}

/// "Also near day N": up to four places, one tap each. The generation's
/// leftovers show at once; what Loci has stored around the day is asked for
/// once, only when those are not enough. An empty row is no row.
struct DaySuggestionsRow: View {
  let dayNumber: Int
  let dayStops: [Loci_Poi_POIDetailedInfo]
  let onTrip: [Loci_Poi_POIDetailedInfo]
  let extras: [Loci_Poi_POIDetailedInfo]
  let isBusy: Bool
  let onAdd: (Loci_Poi_POIDetailedInfo, _ fromExtras: Bool) -> Void

  @State private var nearby: [Loci_Poi_POIDetailedInfo] = []

  private var centroid: CLLocationCoordinate2D? { DaySuggestions.centroid(of: dayStops) }
  private var picks: [Loci_Poi_POIDetailedInfo] {
    DaySuggestions.pick(centroid: centroid, onTrip: onTrip, extras: extras, nearby: nearby)
  }

  var body: some View {
    let picks = picks
    if !picks.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text("Also near day \(dayNumber)").font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(picks, id: \.stableID) { place in
              Button(place.name, systemImage: "plus") {
                onAdd(place, extras.contains { $0.stableID == place.stableID })
              }
              .buttonStyle(MusePillButtonStyle())
              .disabled(isBusy)
              .accessibilityLabel("Add \(place.name) to day \(dayNumber)")
            }
          }
        }
        .scrollIndicators(.hidden)
      }
      .task { await loadNearby() }
    } else {
      // Nothing from the generation: still worth one look around the day.
      Color.clear.frame(height: 0).task { await loadNearby() }
    }
  }

  private func loadNearby() async {
    guard nearby.isEmpty, let centroid, picks.count < DaySuggestions.count else { return }
    nearby = (try? await NearbyPlacesAPI.places(around: centroid, radiusKm: DaySuggestions.nearbyRadiusKm)) ?? []
  }
}
