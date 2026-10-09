import LociConnectProto
import SwiftUI

/// Opens `lociai.fyi/share/<code>` (web: the OG page's redirect). The server
/// answers with a summary of what was shared; the real screen opens from it.
struct SharedContentView: View {
  typealias Loader = @Sendable (String) async throws -> Loci_Share_SharedContent

  let code: String
  var load: Loader = ShareAPI.sharedContent

  @State private var content: Loci_Share_SharedContent?
  @State private var failure: String?
  @State private var place: OpenedPlace?
  @State private var itinerary: OpenedItinerary?
  @State private var opening = false
  @State private var error: String?

  var body: some View {
    Group {
      if let content {
        ScrollView { card(content).padding(LociTheme.defaultPadding) }
      } else if let failure {
        ContentUnavailableView(failure, systemImage: "link.badge.plus", description: Text("Ask whoever sent it for a fresh link."))
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(Color.lociPaper.ignoresSafeArea())
    .navigationTitle("Shared with you")
    .navigationBarTitleDisplayMode(.inline)
    .task(id: code) { await fetch() }
    .sheet(item: $place) { opened in
      PlaceDetailSheet(stop: opened.stop, destination: Self.destination(for: content?.metadata.contentType ?? .poi), cityName: "")
    }
    .navigationDestination(item: $itinerary) { SavedItineraryView(itinerary: $0.itinerary) }
    .errorAlert($error)
  }

  @ViewBuilder private func card(_ content: Loci_Share_SharedContent) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(Self.kicker(for: content)).lociCoordStyle(10)
      Text(Self.title(for: content)).font(.lociTitle(24)).foregroundStyle(Color.lociInk)
      if let detail = Self.detail(for: content), !detail.isEmpty {
        Text(detail).font(.lociBody(14)).foregroundStyle(Color.lociMutedInk)
      }
      if let summary = Self.summary(for: content) {
        Text(summary).lociCoordStyle(10)
      }
      openButton(content)
    }
    .lociCard()
  }

  @ViewBuilder private func openButton(_ content: Loci_Share_SharedContent) -> some View {
    if content.hasList {
      NavigationLink { ListDetailView(listID: content.list.id) } label: { openLabel("Open the list") }
        .buttonStyle(.borderedProminent).tint(Color.lociForest)
    } else if content.hasItinerary {
      Button { Task { await openItinerary(content.itinerary.id) } } label: { openLabel(opening ? "Opening…" : "Open the itinerary") }
        .buttonStyle(.borderedProminent).tint(Color.lociForest).disabled(opening)
    } else if let id = Self.placeID(for: content) {
      Button { Task { await openPlace(id) } } label: { openLabel(opening ? "Opening…" : "Open the place") }
        .buttonStyle(.borderedProminent).tint(Color.lociForest).disabled(opening)
    }
  }

  private func openLabel(_ text: String) -> some View {
    Label(text, systemImage: "arrow.up.right.square").font(.lociCaption(14).weight(.semibold))
  }

  // MARK: - Words

  static func kicker(for content: Loci_Share_SharedContent) -> String {
    switch content.metadata.contentType {
    case .hotel: "A hotel"
    case .restaurant: "A restaurant"
    case .activity: "An activity"
    case .itinerary, .trip: "An itinerary"
    case .list: content.list.isItinerary ? "An itinerary list" : "A list"
    case .poi, .unspecified, .UNRECOGNIZED: "A place"
    }
  }

  static func title(for content: Loci_Share_SharedContent) -> String {
    if content.hasList { return content.list.name }
    if content.hasItinerary { return content.itinerary.title }
    if content.hasHotel { return content.hotel.name }
    if content.hasRestaurant { return content.restaurant.name }
    if content.hasPoi { return content.poi.name }
    return content.metadata.title.isEmpty ? "Shared from Loci" : content.metadata.title
  }

  static func detail(for content: Loci_Share_SharedContent) -> String? {
    if content.hasList { return content.list.description_p }
    if content.hasItinerary { return content.itinerary.description_p }
    if content.hasHotel { return content.hotel.address }
    if content.hasRestaurant { return content.restaurant.address }
    if content.hasPoi { return content.poi.address }
    return content.metadata.description_p
  }

  /// "3 days · 11 stops", "8 places", "4.6 · Portuguese".
  static func summary(for content: Loci_Share_SharedContent) -> String? {
    if content.hasItinerary {
      let it = content.itinerary
      var parts: [String] = []
      if !it.cityName.isEmpty { parts.append(it.cityName) }
      if it.durationDays > 0 { parts.append(it.durationDays == 1 ? "1 day" : "\(it.durationDays) days") }
      if it.stopCount > 0 { parts.append(it.stopCount == 1 ? "1 stop" : "\(it.stopCount) stops") }
      return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    if content.hasList { return content.list.itemCount == 1 ? "1 place" : "\(content.list.itemCount) places" }
    if content.hasRestaurant {
      return [ratingText(content.restaurant.rating), content.restaurant.cuisineType]
        .filter { !$0.isEmpty }.joined(separator: " · ")
    }
    if content.hasHotel {
      return [ratingText(content.hotel.rating), content.hotel.priceRange]
        .filter { !$0.isEmpty }.joined(separator: " · ")
    }
    if content.hasPoi { return content.poi.category }
    return nil
  }

  /// "4.6" ("4,6" where the locale says so); empty when unrated.
  private static func ratingText(_ rating: Double) -> String {
    rating > 0 ? rating.formatted(.number.precision(.fractionLength(1))) : ""
  }

  static func placeID(for content: Loci_Share_SharedContent) -> String? {
    if content.hasPoi { return content.poi.id }
    if content.hasHotel { return content.hotel.id }
    if content.hasRestaurant { return content.restaurant.id }
    return nil
  }

  static func destination(for type: Loci_Share_ShareContentType) -> SearchDestination {
    switch type {
    case .hotel: .hotels
    case .restaurant: .restaurants
    case .activity: .activities
    default: .itinerary
    }
  }

  /// The `content_type` analytics value: the raw type, not the kicker's copy
  /// (same spelling as `ListPayload.analyticsName`).
  static func analyticsName(for type: Loci_Share_ShareContentType) -> String {
    switch type {
    case .hotel: "hotel"
    case .restaurant: "restaurant"
    case .activity: "activity"
    case .itinerary: "itinerary"
    case .trip: "trip"
    case .list: "list"
    case .poi, .unspecified, .UNRECOGNIZED: "poi"
    }
  }

  // MARK: - Actions

  private func fetch() async {
    do {
      let loaded = try await load(code)
      content = loaded
      Analytics.capture(.sharedContentOpened, ["content_type": Self.analyticsName(for: loaded.metadata.contentType)])
    } catch {
      if !error.isCancellation { failure = error.userMessage }
    }
  }

  private func openPlace(_ id: String) async {
    opening = true
    defer { opening = false }
    if let stop = await ReviewsAPI.place(poiID: id) { place = OpenedPlace(stop: stop) } else { error = "Could not load this place." }
  }

  private func openItinerary(_ id: String) async {
    opening = true
    defer { opening = false }
    do {
      itinerary = OpenedItinerary(itinerary: try await ShareAPI.itinerary(id: id))
    } catch {
      if !error.isCancellation { self.error = error.userMessage }
    }
  }
}

/// Protobuf messages are not Identifiable; these name what a sheet or push shows.
private struct OpenedPlace: Identifiable {
  let stop: Loci_Poi_POIDetailedInfo
  var id: String { stop.id }
}

private struct OpenedItinerary: Identifiable, Hashable {
  let itinerary: Loci_Itinerary_UserSavedItinerary
  var id: String { itinerary.id }
}
