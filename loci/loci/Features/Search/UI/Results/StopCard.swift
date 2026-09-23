import LociConnectProto
import SwiftUI

/// Web's `StopCard`: photo with the running index stamped on it, category
/// kicker, name, a two-line blurb and one meta row that depends on the domain.
struct StopCard: View {
  let stop: Loci_Poi_POIDetailedInfo
  let index: Int
  let color: Color
  let destination: SearchDestination
  var isSelected = false
  var onSelect: () -> Void = {}

  var body: some View {
    Button(action: onSelect) {
      HStack(alignment: .top, spacing: 12) {
        PlaceImage(stop: stop, index: index, color: color)
        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline) {
            Label(stop.category.isEmpty ? destination.title : stop.category, systemImage: PlaceSymbol.name(for: stop.category))
              .lociCoordStyle(10).lineLimit(1)
            Spacer(minLength: 4)
            if stop.rating > 0 { RatingChip(rating: stop.rating) }
          }
          Text(stop.name).font(.lociHeadline(16)).foregroundStyle(Color.lociInk).lineLimit(2).multilineTextAlignment(.leading)
          if !stop.blurb.isEmpty {
            Text(stop.blurb).font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk).lineLimit(2).multilineTextAlignment(.leading)
          }
          if let meta = StopMeta.line(for: stop, destination: destination) {
            Text(meta).font(.lociCaption(12)).foregroundStyle(Color.lociForest).lineLimit(1)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .lociCard(padding: 10)
      .overlay(
        RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous)
          .stroke(isSelected ? Color.lociForest : .clear, lineWidth: 2)
      )
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(index). \(stop.name)")
    .accessibilityHint("Shows details")
  }
}

/// The 88-point photo. Credits come first (web renders `image_credits[0]`),
/// then a bare `images[0]`; with nothing, a gradient hashed from the place.
struct PlaceImage: View {
  let stop: Loci_Poi_POIDetailedInfo
  let index: Int
  let color: Color
  var size: CGFloat = 88

  var body: some View {
    ZStack(alignment: .topLeading) {
      picture
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      Text("\(index)")
        .font(.lociCoord(11)).foregroundStyle(LociTheme.stampInk)
        .frame(width: 22, height: 22)
        .background(color, in: Circle())
        .padding(6)
        .accessibilityHidden(true)
      if stop.imageCredits.first != nil {
        Image(systemName: "info.circle.fill")
          .font(.caption2).foregroundStyle(.white.opacity(0.9))
          .padding(5)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
          .accessibilityLabel("Photo credit available")
      }
    }
    .frame(width: size, height: size)
  }

  @ViewBuilder private var picture: some View {
    if let url = stop.imageURL {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image): image.resizable().scaledToFill()
        case .failure: missing
        default: gradient
        }
      }
    } else {
      gradient
    }
  }

  private var missing: some View {
    gradient.overlay { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(Color.lociPaper.opacity(0.8)) }
  }

  private var gradient: some View {
    let hash = stop.stableID.unicodeScalars.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1.value) }
    let a = LociTheme.dayColors[abs(hash) % LociTheme.dayColors.count]
    let b = LociTheme.dayColors[abs(hash / 7) % LociTheme.dayColors.count]
    return LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
  }
}

struct RatingChip: View {
  let rating: Double

  var body: some View {
    Label(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
      .font(.lociCaption(11)).foregroundStyle(Color.lociInk)
      .padding(.horizontal, 6).padding(.vertical, 2)
      .background(Color.lociSage, in: Capsule())
  }
}

/// SF Symbol for a category. Shared by Nearby and the result pages.
nonisolated enum PlaceSymbol {
  static func name(for category: String) -> String {
    switch category.lowercased() {
    case let c where c.contains("restaurant") || c.contains("food") || c.contains("cafe") || c.contains("dining"): "fork.knife"
    case let c where c.contains("hotel") || c.contains("accommodation") || c.contains("hostel"): "bed.double"
    case let c where c.contains("museum") || c.contains("gallery"): "building.columns"
    case let c where c.contains("park") || c.contains("nature") || c.contains("garden"): "tree"
    case let c where c.contains("bar") || c.contains("night") || c.contains("wine"): "wineglass"
    case let c where c.contains("church") || c.contains("cathedral") || c.contains("temple"): "building"
    case let c where c.contains("market") || c.contains("shop"): "basket"
    case let c where c.contains("beach") || c.contains("river") || c.contains("lake"): "water.waves"
    case let c where c.contains("view") || c.contains("lookout") || c.contains("hike"): "binoculars"
    default: "mappin"
    }
  }
}

/// The one meta line under a card, per domain (web's `meta` slot).
nonisolated enum StopMeta {
  static func line(for stop: Loci_Poi_POIDetailedInfo, destination: SearchDestination) -> String? {
    var parts: [String] = []
    switch destination {
    case .hotels:
      if stop.hasStarRating, !stop.starRating.isEmpty { parts.append("\(stop.starRating)★") }
      let amenities = stop.amenities.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
      if !amenities.isEmpty { parts.append(amenities.prefix(4).joined(separator: " · ")) }
    case .restaurants:
      if stop.hasCuisineType, !stop.cuisineType.isEmpty { parts.append(stop.cuisineType) }
      if let hours = todaysHours(stop.openingHours) { parts.append(hours) }
      if let price = price(stop) { parts.append(price) }
    case .activities:
      if !stop.category.isEmpty { parts.append(stop.category) }
      if let price = price(stop) { parts.append(price) }
    case .itinerary:
      if stop.distance > 0 { parts.append(String(format: "%.1f km", stop.distance)) }
      if let price = price(stop) { parts.append(price) }
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  static func price(_ stop: Loci_Poi_POIDetailedInfo) -> String? {
    let value = stop.priceLevel.isEmpty ? stop.priceRange : stop.priceLevel
    return value.isEmpty ? nil : value
  }

  /// Today's entry of an `opening_hours` map keyed by weekday name, in any case.
  static func todaysHours(_ hours: [String: String], now: Date = Date(), calendar: Calendar = .current) -> String? {
    guard !hours.isEmpty else { return nil }
    let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: now) - 1].lowercased()
    let short = String(weekday.prefix(3))
    if let match = hours.first(where: { $0.key.lowercased() == weekday || $0.key.lowercased() == short })?.value, !match.isEmpty {
      return "Today \(match)"
    }
    return nil
  }
}

nonisolated extension Loci_Poi_POIDetailedInfo {
  /// `description_poi` when the model filled it, else the generic description.
  var blurb: String { hasDescriptionPoi && !descriptionPoi.isEmpty ? descriptionPoi : description_p }

  /// The photo to show: a credited image first, then a bare URL.
  var imageURL: URL? {
    if let credited = imageCredits.first, let url = URL(string: credited.url), !credited.url.isEmpty { return url }
    if let bare = images.first(where: { !$0.isEmpty }) { return URL(string: bare) }
    return nil
  }

  var hasPhoto: Bool { imageURL != nil }
}

/// One day of stops with its header. Index stamps keep counting across days.
struct DaySection: View {
  let group: DayGroup
  let sequence: [String: Int]
  let destination: SearchDestination
  let showsDayLabel: Bool
  @Binding var selectedID: String?
  var onOpen: (Loci_Poi_POIDetailedInfo) -> Void

  private var color: Color { showsDayLabel ? LociTheme.dayColor(group.number) : LociTheme.ungroupedColor }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if showsDayLabel {
        HStack(spacing: 8) {
          Circle().fill(color).frame(width: 10, height: 10)
          Text("Day \(group.number)").font(.lociHeadline(15)).foregroundStyle(Color.lociInk)
          Text("\(group.stops.count) \(group.stops.count == 1 ? "stop" : "stops")").lociCoordStyle(10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
      }
      ForEach(group.stops, id: \.stableID) { stop in
        StopCard(
          stop: stop,
          index: sequence[stop.stableID] ?? 0,
          color: color,
          destination: destination,
          isSelected: selectedID == stop.stableID
        ) {
          selectedID = stop.stableID
          onOpen(stop)
        }
        .id(stop.stableID)
      }
    }
  }
}
