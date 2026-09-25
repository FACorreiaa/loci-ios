import SwiftUI

/// The signed-in pages web has and the tab bar does not: Profile is their hub.
/// Every row is real now (parity plan, pass 2): Recents since Phase 1, Lists
/// since Phase 2, My reviews since Phase 5, Contribute since Phase 6 and Where
/// you've been since Phase 7. `ComingSoonView` stays for AppLinkDestination.
enum YouDestination: String, CaseIterable, Identifiable {
  case recents, travelHistory, lists, reviews, contribute

  var id: String { rawValue }

  var title: String {
    switch self {
    case .recents: "Recents"
    case .travelHistory: "Where you've been"
    case .lists: "Lists"
    case .reviews: "My reviews"
    case .contribute: "Contribute"
    }
  }

  var systemImage: String {
    switch self {
    case .recents: "clock.arrow.circlepath"
    case .travelHistory: "globe.europe.africa"
    case .lists: "list.bullet.rectangle"
    case .reviews: "star.bubble"
    case .contribute: "checkmark.seal"
    }
  }

  @ViewBuilder var screen: some View {
    switch self {
    case .recents: RecentsView()
    case .lists: ListsView()
    case .reviews: MyReviewsView()
    case .contribute: ContributeView()
    case .travelHistory: GlobeView()
    }
  }
}

/// Profile's "You" rows, above Settings.
struct YouSection: View {
  var body: some View {
    Section("You") {
      ForEach(YouDestination.allCases) { destination in
        NavigationLink {
          destination.screen
        } label: {
          Label(destination.title, systemImage: destination.systemImage)
        }
      }
    }
    .listRowBackground(Color.lociCard)
  }
}
