import SwiftUI

/// The sheet under the globe (web: ActivitiesDrawer, non-modal as there so the
/// globe still pans behind it): the stats, then every leg, newest first.
/// Tapping a leg selects it and fits the globe to it; tapping it again clears it.
struct LegsSheet: View {
  let data: GlobeData
  let selectedLegID: String?
  let onSelect: (GlobeLeg?) -> Void

  var body: some View {
    ScrollViewReader { proxy in
      List {
        TravelStatsCard(summary: data.summary).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

        Section {
          if data.legs.isEmpty {
            Text("No legs yet. Trips with real dates in the past show up here, one line per move between cities.").font(.lociBody(15))
              .foregroundStyle(Color.lociMutedInk)
          }
          ForEach(data.legs) { leg in
            Button {
              onSelect(leg.id == selectedLegID ? nil : leg)
            } label: {
              LegRow(leg: leg, isSelected: leg.id == selectedLegID)
            }.buttonStyle(.plain).id(leg.id).listRowBackground(leg.id == selectedLegID ? Color.lociSage : Color.lociCard)
          }
        } header: {
          Text(countsText)
        }.listRowBackground(Color.lociCard)
      }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Color.lociPaper).onChange(of: selectedLegID) { _, id in
        if let id { proxy.scrollTo(id) }
      }
    }
  }

  private var countsText: String {
    let legs = data.legs.count == 1 ? "1 leg" : "\(data.legs.count) legs"
    let cities = data.cities.count == 1 ? "1 city" : "\(data.cities.count) cities"
    return "\(legs) · \(cities)"
  }
}

/// From / To on top; Mode, Distance and When under it.
private struct LegRow: View {
  let leg: GlobeLeg
  let isSelected: Bool

  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: LegMode.symbol(leg.mode)).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.lociCoral).frame(
        width: 30,
        height: 30
      ).background(Color.lociMuted, in: Circle()).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(leg.fromName.isEmpty ? "—" : leg.fromName)
          Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.lociMutedInk)
          Text(leg.toName.isEmpty ? "—" : leg.toName)
        }.font(.lociHeadline(16)).foregroundStyle(Color.lociInk).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
        Text(detail).font(.lociCaption(12)).monospacedDigit().foregroundStyle(Color.lociMutedInk)
      }
      Spacer(minLength: 4)
      if isSelected { Image(systemName: "scope").foregroundStyle(Color.lociForest).accessibilityHidden(true) }
    }.padding(.vertical, 2).contentShape(Rectangle()).accessibilityElement(children: .ignore).accessibilityLabel(
      "\(leg.fromName) to \(leg.toName), \(detail)"
    ).accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton).accessibilityHint(
      isSelected ? "Clears the selection" : "Shows this leg on the globe"
    )
  }

  /// Mode (capitalised, "—" when none was recorded), distance, date.
  private var detail: String {
    let mode = leg.mode.isEmpty ? "—" : leg.mode.capitalized
    let when = leg.occurredAt?.formatted(date: .abbreviated, time: .omitted) ?? "—"
    return "\(mode) · \(GlobeFormat.distance(leg.distanceKm)) · \(when)"
  }
}

/// SF Symbols for the modes trips record. Unknown or empty falls back to a plain path.
enum LegMode {
  static func symbol(_ mode: String) -> String {
    switch mode.lowercased() {
    case "fly", "flight", "plane", "air": "airplane"
    case "drive", "car", "driving": "car.fill"
    case "rail", "train": "tram.fill"
    case "bus", "coach": "bus.fill"
    case "ferry", "boat", "ship": "ferry.fill"
    case "walk", "walking": "figure.walk"
    case "bike", "cycle", "bicycle": "bicycle"
    default: "point.topleft.down.to.point.bottomright.curvepath"
    }
  }
}
