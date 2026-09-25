import CoreLocation
import LociConnectProto
import MapKit
import SwiftUI

/// The proto's own `id` field satisfies `Identifiable` for `.sheet(item:)`;
/// lists key on `stableID`, which also covers places without an id.
nonisolated extension Loci_Poi_POIDetailedInfo: @retroactive Identifiable {}

/// Web's `DetailedItemModal`: a credited gallery, stat tiles, the grounded
/// badge, verified facts, contact rows, reviews, and Save / Add to list / Add to trip / Share / Maps at the bottom.
struct PlaceDetailSheet: View {
  let stop: Loci_Poi_POIDetailedInfo
  let destination: SearchDestination
  let cityName: String

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      PlaceDetailView(stop: stop, destination: destination, cityName: cityName)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
    }
    .adaptiveDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }
}

/// The detail itself, for a sheet or for pushing onto a stack. With
/// `savedItem` it is a saved place: the heart starts filled, toggles the
/// favourite off and on again, and the note the user wrote is shown.
struct PlaceDetailView: View {
  let stop: Loci_Poi_POIDetailedInfo
  let destination: SearchDestination
  let cityName: String
  var savedItem: Loci_Favorites_V1_FavoriteItem?
  var onSavedChange: ((Bool) -> Void)?

  @Environment(\.openURL) private var openURL
  @State private var facts: Loci_Place_PlaceFacts?
  /// Apple's street-level imagery; nil where there is no coverage, and then
  /// the section is simply absent.
  @State private var lookAround: MKLookAroundScene?
  @State private var saved: Bool
  @State private var saving = false
  @State private var addingToList = false
  @State private var addingToTrip = false
  @State private var reporting = false
  @State private var error: String?

  init(
    stop: Loci_Poi_POIDetailedInfo,
    destination: SearchDestination,
    cityName: String,
    savedItem: Loci_Favorites_V1_FavoriteItem? = nil,
    onSavedChange: ((Bool) -> Void)? = nil
  ) {
    self.stop = stop
    self.destination = destination
    self.cityName = cityName
    self.savedItem = savedItem
    self.onSavedChange = onSavedChange
    _saved = State(initialValue: savedItem != nil)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        gallery
        VStack(alignment: .leading, spacing: 6) {
          Label(stop.category.isEmpty ? destination.title : stop.category, systemImage: PlaceSymbol.name(for: stop.category)).lociCoordStyle(10)
          Text(stop.name).font(.lociTitle(22)).foregroundStyle(Color.lociInk)
          if !stop.address.isEmpty { Text(stop.address).font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk) }
          GroundedBadge(stop: stop)
        }
        stats
        if let lookAround {
          LookAroundPreview(initialScene: lookAround)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
            .accessibilityLabel("Look Around at \(stop.name)")
        }
        if !stop.blurb.isEmpty {
          section("About") { Text(stop.blurb).font(.lociBody(15)).foregroundStyle(Color.lociInk) }
        }
        if let notes = savedItem?.notes, !notes.isEmpty {
          section("Your notes") { Text(notes).font(.lociBody(15)).foregroundStyle(Color.lociInk) }
        }
        if let facts, !facts.facts.isEmpty { PlaceFactsList(facts: facts) }
        // Field reports hang off a stored POI, the same rule as Add to list and Reviews.
        if ContributePayload.canReport(stop) {
          Button("Report a fact", systemImage: "checkmark.seal") { reporting = true }
            .font(.lociCaption(14).weight(.semibold))
            .buttonStyle(.bordered)
            .tint(Color.lociForest)
            .accessibilityHint("Tell other travellers what's true here now: hours, access, noise, crowds.")
        }
        contact
        chips
        // Reviews hang off a stored POI, the same rule as Add to list.
        if ReviewPayload.canReview(stop) {
          PlaceReviewsSection(
            poiID: stop.id,
            placeName: stop.name,
            service: ResultsSideData.isOffline ? PreviewReviewsService() : ConnectReviewsService()
          )
          .padding(.top, 8)
        }
      }
      .padding(LociTheme.defaultPadding)
    }
    .background(Color.lociPaper.ignoresSafeArea())
    .safeAreaInset(edge: .bottom) { footer }
    .sheet(isPresented: $addingToList) { AddToListSheet(stop: stop, destination: destination) }
    .sheet(isPresented: $addingToTrip) { AddToTripSheet(stop: stop, cityName: cityName) }
    .sheet(isPresented: $reporting) { ReportFactSheet(stop: stop) { Task { await loadFacts() } } }
    .errorAlert($error)
    .task(id: stop.id) {
      async let scene: Void = loadLookAround()
      await loadFacts()
      await scene
    }
  }

  // MARK: - Pieces

  @ViewBuilder private var gallery: some View {
    if !stop.imageCredits.isEmpty {
      TabView {
        ForEach(Array(stop.imageCredits.enumerated()), id: \.offset) { _, credit in
          CreditedImage(credit: credit)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: stop.imageCredits.count > 1 ? .automatic : .never))
      .frame(height: 240)
      .clipShape(RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
    } else if let url = stop.imageURL {
      AsyncImage(url: url) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        Color.lociMuted
      }
      .frame(height: 220).frame(maxWidth: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
    }
  }

  private var stats: some View {
    HStack(spacing: 8) {
      if stop.rating > 0 { StatTile(kicker: "Rating", value: stop.rating.formatted(.number.precision(.fractionLength(1))), symbol: "star.fill") }
      if let price = StopMeta.price(stop) { StatTile(kicker: "Price", value: price, symbol: "creditcard") }
      if stop.distance > 0 { StatTile(kicker: "Distance", value: String(format: "%.1f km", stop.distance), symbol: "figure.walk") }
      if stop.hasStarRating, !stop.starRating.isEmpty { StatTile(kicker: "Stars", value: stop.starRating, symbol: "bed.double") }
    }
  }

  @ViewBuilder private var contact: some View {
    let hours = stop.openingHours.sorted { Weekday.order($0.key) < Weekday.order($1.key) }
    if !stop.phoneNumber.isEmpty || !stop.website.isEmpty || !hours.isEmpty || (stop.hasCuisineType && !stop.cuisineType.isEmpty) {
      section("Details") {
        VStack(alignment: .leading, spacing: 8) {
          if stop.hasCuisineType, !stop.cuisineType.isEmpty { ContactRow(symbol: "fork.knife", text: stop.cuisineType) }
          if !stop.phoneNumber.isEmpty {
            ContactRow(symbol: "phone", text: stop.phoneNumber, url: URL(string: "tel:\(stop.phoneNumber.filter { !$0.isWhitespace })"))
          }
          if !stop.website.isEmpty { ContactRow(symbol: "safari", text: stop.website, url: URL(string: stop.website)) }
          ForEach(hours, id: \.key) { day, value in ContactRow(symbol: "clock", text: "\(day.capitalized): \(value)") }
        }
      }
    }
  }

  @ViewBuilder private var chips: some View {
    let amenities = stop.amenities.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    let all = stop.tags + amenities
    if !all.isEmpty {
      FlowChips(items: all)
    }
  }

  private var footer: some View {
    HStack(spacing: 8) {
      Button(saved ? "Saved" : "Save", systemImage: saved ? "heart.fill" : "heart") { Task { await save() } }
        .disabled((saved && savedItem == nil) || saving)
        .accessibilityHint(savedItem != nil && saved ? "Removes it from Saved" : "")
      // Lists key on the stored POI id; a name-keyed place cannot go in one.
      if ListPayload.canAdd(stop) { Button("Add to list", systemImage: "text.badge.plus") { addingToList = true } }
      // A trip stop needs only a name, so any place can go in one.
      Button("Add to trip", systemImage: "calendar.badge.plus") { addingToTrip = true }
      ShareLink(item: shareText) { Label("Share", systemImage: "square.and.arrow.up") }
      if GoogleMapsRoute.hasCoordinate(stop) {
        Button("Apple Maps", systemImage: "map") { openInAppleMaps() }
      }
      if let google = GoogleMapsRoute.url(for: [stop], cityName: cityName) {
        Button("Google", systemImage: "arrow.up.right.square") { openURL(google) }
      }
    }
    .buttonStyle(MusePillButtonStyle())
    .labelStyle(.iconOnly)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, LociTheme.defaultPadding).padding(.vertical, 10)
    .background(Color.lociPaper)
  }

  private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).lociCoordStyle(10)
      content()
    }
  }

  private var shareText: String {
    [stop.name, stop.address, ShareText.signature, ShareText.homeURL].filter { !$0.isEmpty }.joined(separator: "\n")
  }

  // MARK: - Actions

  private func loadFacts() async {
    // Facts hang off a stored POI; a name-keyed saved place has none to ask about.
    guard SavedPlace.isStoredID(stop.id), !ResultsSideData.isOffline else { return }
    facts = try? await ResultsAPI.placeFacts(poiID: stop.id)
  }

  private func loadLookAround() async {
    guard GoogleMapsRoute.hasCoordinate(stop) else { return }
    lookAround = await Self.lookAroundScene(at: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude))
  }

  /// Off the main actor: the request and its scene aren't Sendable, so both
  /// live here and only the finished scene is handed back.
  @concurrent static func lookAroundScene(at coordinate: CLLocationCoordinate2D) async -> sending MKLookAroundScene? {
    try? await MKLookAroundSceneRequest(coordinate: coordinate).scene
  }

  private func save() async {
    saving = true
    defer { saving = false }
    do {
      if let savedItem {
        if saved { try await SavedPlaceAPI.remove(savedItem) } else { try await SavedPlaceAPI.restore(savedItem) }
        saved.toggle()
        onSavedChange?(saved)
      } else {
        try await ResultsAPI.addFavorite(stop, destination: destination, cityName: cityName)
        saved = true
      }
    } catch { self.error = error.userMessage }
  }

  private func openInAppleMaps() {
    let location = CLLocation(latitude: stop.latitude, longitude: stop.longitude)
    let item = MKMapItem(location: location, address: stop.address.isEmpty ? nil : MKAddress(fullAddress: stop.address, shortAddress: nil))
    item.name = stop.name
    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
  }
}

/// One credited image with its attribution and licence underneath.
private struct CreditedImage: View {
  let credit: Loci_Poi_POIImage

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      AsyncImage(url: URL(string: credit.url)) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        Color.lociMuted
      }
      .frame(maxWidth: .infinity).frame(height: 240).clipped()
      if !credit.attribution.isEmpty || !credit.licence.isEmpty {
        let text = [credit.attribution, credit.licence].filter { !$0.isEmpty }.joined(separator: " · ")
        Group {
          if let page = URL(string: credit.sourcePageURL), !credit.sourcePageURL.isEmpty {
            Link(text, destination: page)
          } else {
            Text(text)
          }
        }
        .font(.lociCaption(10)).foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.black.opacity(0.55), in: Capsule())
        .padding(8)
        .lineLimit(1)
      }
    }
  }
}

/// Web's `GroundedBadge`: verified place, AI suggestion, or nothing when the
/// server said neither.
struct GroundedBadge: View {
  let stop: Loci_Poi_POIDetailedInfo

  var body: some View {
    if stop.hasGrounded {
      Label(stop.grounded ? "Verified place" : "AI suggestion", systemImage: stop.grounded ? "checkmark.seal.fill" : "sparkles")
        .font(.lociCaption(11))
        .foregroundStyle(stop.grounded ? Color.lociForest : Color.lociMutedInk)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(stop.grounded ? Color.lociSage : Color.lociMuted, in: Capsule())
    }
  }
}

private struct StatTile: View {
  let kicker: String
  let value: String
  let symbol: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Label(kicker, systemImage: symbol).lociCoordStyle(9)
      Text(value).font(.lociHeadline(15)).foregroundStyle(Color.lociInk).lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(Color.lociMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

private struct ContactRow: View {
  let symbol: String
  let text: String
  var url: URL?

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: symbol).foregroundStyle(Color.lociForest).frame(width: 18)
      if let url {
        Link(text, destination: url).font(.lociBody(14)).lineLimit(1)
      } else {
        Text(text).font(.lociBody(14)).foregroundStyle(Color.lociInk)
      }
    }
  }
}

/// Community facts from PlaceIntelligence, with how sure they are.
private struct PlaceFactsList: View {
  let facts: Loci_Place_PlaceFacts

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Verified by travellers").lociCoordStyle(10)
      ForEach(Array(facts.facts.enumerated()), id: \.offset) { _, fact in
        HStack(alignment: .firstTextBaseline) {
          Text(Self.label(fact.field)).font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk).frame(width: 96, alignment: .leading)
          Text(PlaceFactVocabulary.displayValue(fact.field, fact.value)).font(.lociBody(14)).foregroundStyle(Color.lociInk)
          Spacer()
          Text("\(Int((fact.confidence * 100).rounded()))%").lociCoordStyle(9)
        }
      }
    }
  }

  static func label(_ field: Loci_Place_PlaceFactField) -> String {
    switch field {
    case .openingHours: "Hours"
    case .priceLevel: "Price"
    case .accessibility: "Access"
    case .dietary: "Dietary"
    case .crowdLevel: "Crowds"
    case .noiseLevel: "Noise"
    case .childFriendly: "Kids"
    case .dogFriendly: "Dogs"
    case .vibe: "Vibe"
    default: "Fact"
    }
  }
}

/// "Report a fact" from a place: every field we know how to ask about, for this POI.
private struct ReportFactSheet: View {
  let stop: Loci_Poi_POIDetailedInfo
  let onSubmitted: () -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ClaimFormView(
        task: VerificationTask.fromPlace(id: stop.id, name: stop.name),
        service: ResultsSideData.isOffline ? PreviewContributeService() : ConnectContributeService(),
        onSubmitted: onSubmitted
      )
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
    }
    .presentationDetents([.large])
  }
}

private struct FlowChips: View {
  let items: [String]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(Array(items.prefix(12).enumerated()), id: \.offset) { _, item in
          Text(item).font(.lociCaption(11)).foregroundStyle(Color.lociInk)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.lociMuted, in: Capsule())
        }
      }
    }
    .scrollClipDisabled()
  }
}

nonisolated enum Weekday {
  private static let names = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

  static func order(_ key: String) -> Int {
    let lower = key.lowercased()
    return names.firstIndex { $0 == lower || $0.hasPrefix(lower) } ?? names.count
  }
}
