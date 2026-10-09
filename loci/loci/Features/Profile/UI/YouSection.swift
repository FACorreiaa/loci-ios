import SwiftUI

/// The signed-in pages web has and the tab bar does not: Profile is their hub.
/// Every row is real now (parity plan, pass 2): Recents since Phase 1, Lists
/// since Phase 2, My reviews since Phase 5, Contribute since Phase 6 and Where
/// you've been since Phase 7. `ComingSoonView` stays for AppLinkDestination.
enum YouDestination: String, CaseIterable, Identifiable {
  case friends, leaderboard, progress, boards, recents, travelHistory, lists, reviews, contribute

  var id: String { rawValue }

  var title: String {
    switch self {
    case .friends: "Friends"
    case .leaderboard: "Leaderboard"
    case .progress: "Your progress"
    case .boards: "Boards"
    case .recents: "Recents"
    case .travelHistory: "Where you've been"
    case .lists: "Lists"
    case .reviews: "My reviews"
    case .contribute: "Contribute"
    }
  }

  var systemImage: String {
    switch self {
    case .friends: "person.2"
    case .leaderboard: "trophy"
    case .progress: "rosette"
    case .boards: BoardsHomeView.symbol
    case .recents: "clock.arrow.circlepath"
    case .travelHistory: "globe.europe.africa"
    case .lists: "list.bullet.rectangle"
    case .reviews: "star.bubble"
    case .contribute: "checkmark.seal"
    }
  }

  @ViewBuilder var screen: some View {
    switch self {
    case .friends: FriendsView()
    case .leaderboard: LeaderboardView()
    case .progress: MyProgressView()
    case .boards: BoardsHomeView()
    case .recents: RecentsView()
    case .lists: ListsView()
    case .reviews: MyReviewsView()
    case .contribute: ContributeView()
    case .travelHistory: GlobeView()
    }
  }
}

/// Profile's "You" rows, above Settings, headed by the account's plan chip.
struct YouSection: View {
  var entitlements: Entitlements?
  @State private var showsInvite = false

  private var plan: Entitlements { entitlements ?? EntitlementsStore.shared.current }

  var body: some View {
    Section("You") {
      PlanChip(entitlements: plan)
      ForEach(YouDestination.allCases) { destination in
        NavigationLink(value: AppRoute.you(destination)) {
          Label(destination.title, systemImage: destination.systemImage)
        }
      }
      Button { showsInvite = true } label: {
        Label("Invite", systemImage: "square.and.arrow.up")
      }
    }
    .listRowBackground(Color.lociCard)
    .sheet(isPresented: $showsInvite) { InviteSheet() }
  }
}

/// "Pro", or "Free · 3/5 lists · 12/50 places". Read-only: the app does not
/// sell the upgrade (web: EntitlementsBadge without its link).
struct PlanChip: View {
  let entitlements: Entitlements

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: entitlements.isPro ? "star.circle.fill" : "person.crop.circle")
        .foregroundStyle(entitlements.isPro ? Color.lociForest : Color.lociMutedInk)
      VStack(alignment: .leading, spacing: 2) {
        Text("Plan").lociCoordStyle(10)
        Text(entitlements.chipText).font(.lociBody(15)).foregroundStyle(Color.lociInk)
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Plan: \(entitlements.chipText)")
  }
}
