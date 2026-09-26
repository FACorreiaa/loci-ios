import LociConnectProto
import SwiftUI

/// A city's typical gastronomy (web: components/gastronomy/GastronomySection):
/// the overview, filter chips for dish type and for ingredient or diet, and
/// one card per dish with the well-known places to eat it.
struct GastronomySection: View {
  let gastronomy: Loci_Gastronomy_CityGastronomy
  /// Under an itinerary or discovery result: a smaller header, no traditions
  /// or tips, and the first few dishes until expanded.
  var compact = false

  @State private var filter = GastronomyFilter()
  @State private var expanded = false

  private static let compactDishes = 4

  private var dishes: [Loci_Gastronomy_Dish] { filter.apply(to: gastronomy) }
  private var visible: [Loci_Gastronomy_Dish] {
    compact && !expanded ? Array(dishes.prefix(Self.compactDishes)) : dishes
  }

  private var city: String { gastronomy.cityName }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      filters
      if dishes.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("No dishes match these filters.").font(.lociBody(15)).foregroundStyle(Color.lociMutedInk)
          Button("Clear filters") { filter = GastronomyFilter() }.font(.lociCaption(13)).underline()
        }
        .lociCard()
      } else {
        ForEach(Array(visible.enumerated()), id: \.offset) { _, dish in
          DishCard(dish: dish, city: city)
        }
      }
      if compact, dishes.count > Self.compactDishes {
        Button(expanded ? "Show fewer dishes" : "Show all \(dishes.count) dishes", systemImage: expanded ? "chevron.up" : "chevron.down") {
          expanded.toggle()
        }
        .buttonStyle(MusePillButtonStyle())
      }
      if !compact, !filter.isActive {
        InfoList(title: "Traditions", items: gastronomy.culinaryTraditions)
        InfoList(title: "Dining tips", items: gastronomy.diningTips)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Typical gastronomy of \(city)")
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      if compact { Text("Typical gastronomy").lociCoordStyle(10) }
      Text(compact ? "What to eat in \(city)" : "The food of \(city)")
        .font(compact ? .lociHeadline(18) : .lociDisplay(26)).foregroundStyle(Color.lociInk)
      if !gastronomy.overview.isEmpty {
        Text(gastronomy.overview).font(.lociBody(15)).foregroundStyle(Color.lociMutedInk)
      }
    }
  }

  @ViewBuilder private var filters: some View {
    let categories = gastronomy.presentCategories
    let tags = gastronomy.presentTags
    if categories.count > 1 {
      ChipRow(label: "Filter dishes by type") {
        ForEach(categories, id: \.rawValue) { category in
          GastronomyChip(label: category.label, isOn: filter.categories.contains(category)) { filter.toggle(category) }
        }
      }
    }
    if !tags.isEmpty {
      ChipRow(label: "Filter dishes by ingredient or diet") {
        ForEach(tags, id: \.self) { tag in
          GastronomyChip(label: tag.capitalized, isOn: filter.tags.contains(tag)) { filter.toggle(tag: tag) }
        }
      }
    }
  }
}

// MARK: - Pieces

private struct DishCard: View {
  let dish: Loci_Gastronomy_Dish
  let city: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(dish.name).font(.lociHeadline(17)).foregroundStyle(Color.lociInk)
          if !dish.localName.isEmpty, dish.localName != dish.name {
            Text(dish.localName).font(.lociCaption(13)).italic().foregroundStyle(Color.lociMutedInk)
          }
        }
        Spacer(minLength: 8)
        if dish.isSignature {
          Label("Signature", systemImage: "star.fill").font(.lociCaption(12).weight(.semibold)).foregroundStyle(Color.lociForest)
            .labelStyle(.titleAndIcon)
        }
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          TagPill(text: dish.displayCategory.label, emphasised: true)
          ForEach(dish.tags, id: \.self) { TagPill(text: $0.capitalized) }
        }
      }
      .scrollClipDisabled()
      if !dish.description_p.isEmpty {
        Text(dish.description_p).font(.lociBody(15)).foregroundStyle(Color.lociInk)
      }
      if !dish.places.isEmpty {
        Divider()
        Text("Where to try it").lociCoordStyle(10)
        ForEach(Array(dish.places.enumerated()), id: \.offset) { _, place in
          PlaceRow(place: place, city: city)
        }
      }
    }
    .lociCard()
  }
}

private struct PlaceRow: View {
  let place: Loci_Gastronomy_GastronomyPlace
  let city: String

  private var meta: String {
    [place.neighborhood, place.priceRange].filter { !$0.isEmpty }.joined(separator: " · ")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        if let url = place.mapsURL(city: city) {
          Link(destination: url) {
            Label(place.name, systemImage: "mappin.and.ellipse").font(.lociCaption(14).weight(.semibold))
          }
          .tint(Color.lociInk)
          .accessibilityHint("Opens in Maps")
        } else {
          Text(place.name).font(.lociCaption(14).weight(.semibold)).foregroundStyle(Color.lociInk)
        }
        if !meta.isEmpty { Text(meta).font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk) }
        if place.hasWebsite, let url = URL(string: place.website) {
          Link(destination: url) { Image(systemName: "arrow.up.right.square") }
            .tint(Color.lociMutedInk)
            .accessibilityLabel("\(place.name) website")
        }
      }
      if !place.whyFamous.isEmpty {
        Text(place.whyFamous).font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
      }
    }
    .frame(minHeight: LociTheme.minTapTarget, alignment: .leading)
  }
}

private struct InfoList: View {
  let title: String
  let items: [String]

  var body: some View {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text(title).lociCoordStyle(10)
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          Label { Text(item).font(.lociBody(14)).foregroundStyle(Color.lociInk) } icon: {
            Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Color.lociMutedInk)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .lociCard()
    }
  }
}

private struct ChipRow<Content: View>: View {
  let label: String
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { content }.padding(.vertical, 2) }
      .scrollClipDisabled()
      .accessibilityElement(children: .contain)
      .accessibilityLabel(label)
  }
}

/// A toggle chip, the same shape as the Packs filters.
private struct GastronomyChip: View {
  let label: String
  let isOn: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(label).font(.lociCaption(13)).padding(.horizontal, 12).padding(.vertical, 7)
        .background(isOn ? Color.lociForest : Color.lociMuted, in: Capsule())
        .foregroundStyle(isOn ? Color.lociPaper : Color.lociInk)
        .frame(minHeight: LociTheme.minTapTarget).contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isOn ? .isSelected : [])
  }
}

private struct TagPill: View {
  let text: String
  var emphasised = false

  var body: some View {
    Text(text).font(.lociCaption(12).weight(emphasised ? .semibold : .regular))
      .padding(.horizontal, 8).padding(.vertical, 3)
      .background(Color.lociMuted, in: Capsule())
      .foregroundStyle(Color.lociInk)
  }
}
