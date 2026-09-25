import SwiftUI

/// One city from Recents (web: /recents/:city), Overview and Interactions only.
/// Web's Places, Favorites and Saved Itineraries tabs and its hotel/restaurant/
/// attraction tiles are left out: the server never fills them. The city comes
/// in whole from the Cities list, so there is nothing to fetch and no
/// not-found state.
struct RecentCityView: View {
  enum Tab: String, CaseIterable { case overview = "Overview", interactions = "Interactions" }

  let city: RecentCity
  var now = Date()
  @State private var tab = Tab.overview

  var body: some View {
    List {
      Picker("Section", selection: $tab) {
        ForEach(Tab.allCases, id: \.self) { tab in
          Text(tab == .interactions ? "Interactions (\(city.interactions.count))" : tab.rawValue)
        }
      }
      .pickerStyle(.segmented)
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())

      switch tab {
      case .overview: overview
      case .interactions: interactions(city.interactions)
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(Color.lociPaper.ignoresSafeArea())
    .overlay {
      if tab == .interactions, city.interactions.isEmpty {
        ContentUnavailableView("No interactions", systemImage: "bubble.left", description: Text("Nothing asked about \(city.name) yet."))
      }
    }
    .navigationTitle(city.name)
    .navigationBarTitleDisplayMode(.large)
    .onAppear { Analytics.screen("recents_city") }
  }

  @ViewBuilder private var overview: some View {
    Section {
      AdaptiveStack(spacing: 12) {
        StatTile(value: "\(city.interactionCount)", label: city.interactionCount == 1 ? "Interaction" : "Interactions", systemImage: "bubble.left")
        if let last = city.lastActivity {
          StatTile(value: DayBuckets.relativeTime(last, now: now), label: "Last active", systemImage: "clock")
        }
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())
      Label(city.level.label, systemImage: city.level.systemImage)
        .font(.lociCaption(13))
        .foregroundStyle(Color.lociForest)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 0, trailing: 4))
      if !city.country.isEmpty {
        LabeledContent("Country", value: city.country).listRowBackground(Color.lociCard)
      }
    }

    if !city.interactions.isEmpty {
      interactions(Array(city.interactions.prefix(3)), title: "Latest")
      if city.interactions.count > 3 {
        Section {
          Button("View all \(city.interactions.count) interactions") { tab = .interactions }
        }
        .listRowBackground(Color.lociCard)
      }
    }
  }

  private func interactions(_ items: [CityInteraction], title: String? = nil) -> some View {
    Section {
      ForEach(items) { item in
        HStack(alignment: .top, spacing: 12) {
          RecentsBadgeIcon(systemImage: item.badge.systemImage)
          // The time joins the text column at accessibility sizes.
          AdaptiveStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
              Text(item.prompt).font(.lociBody(15)).foregroundStyle(Color.lociInk)
              Text(item.badge.label).lociCoordStyle(10)
            }
            Spacer(minLength: 0)
            Text(DayBuckets.relativeTime(item.occurredAt, now: now))
              .font(.lociCaption())
              .foregroundStyle(Color.lociMutedInk)
              .fixedSize()
          }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
      }
    } header: {
      if let title { Text(title) }
    }
    .listRowBackground(Color.lociCard)
  }
}

/// A number and what it counts, on a flat card.
private struct StatTile: View {
  let value: String
  let label: String
  let systemImage: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: systemImage).foregroundStyle(Color.lociForest).accessibilityHidden(true)
      Text(value).font(.lociTitle(24)).foregroundStyle(Color.lociInk).lineLimit(1).minimumScaleFactor(0.7)
      Text(label).lociCoordStyle(10)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .lociCard()
    .accessibilityElement(children: .combine)
  }
}
