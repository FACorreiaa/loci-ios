import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Someone's travel profile (web: /u/:username): who they are, where they've
/// been, their achievements and the trips you may see. A private account shows
/// only the card and counts until it approves your follow.
struct UserProfileView: View {
  let username: String

  @State private var profile: Loci_Social_GetPublicProfileResponse?
  @State private var edge = FollowEdge.unknown
  /// The edge the last profile load reported.
  @State private var loadedEdge: FollowEdge?
  @State private var trips: [Loci_Trip_TripDraft] = []
  @State private var rankings = RankingListStore()
  @State private var failure: String?
  @State private var confirmBlock = false
  @State private var error: String?

  var body: some View {
    List {
      if let profile {
        Section {
          VStack(spacing: 10) {
            UserAvatar(user: profile.user, size: 84)
            Text(profile.user.shownName).font(.lociDisplay(24)).foregroundStyle(Color.lociInk)
            Text(subtitle(profile)).font(.lociCaption()).foregroundStyle(Color.lociMutedInk).multilineTextAlignment(.center)
            if edge.state != .isSelf, edge.followsYou, !edge.isFriend {
              Text("Follows you").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
            }
            FollowButton(user: profile.user, edge: $edge)
          }
          .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .listRowBackground(Color.lociCard)

        Section {
          TravelStatsRow(stats: profile.stats)
          FollowCountsRow(user: profile.user, stats: profile.stats, linksOpen: profile.canView)
        }
        .listRowBackground(Color.lociCard)

        if !profile.canView {
          Section {
            Label {
              Text(
                edge.state == .requested
                  ? "This account is private. You'll see their trips and achievements once they approve your request."
                  : "This account is private. Follow to ask to see their trips and achievements."
              )
            } icon: {
              Image(systemName: "lock.fill")
            }
            .font(.lociCaption(15)).foregroundStyle(Color.lociMutedInk)
          }
          .listRowBackground(Color.lociCard)
        } else {
          profileContent(profile)
        }
      } else if let failure {
        ContentUnavailableView(failure, systemImage: "person.crop.circle.badge.questionmark").listRowBackground(Color.clear)
      } else {
        ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
      }
    }
    .settingsStyle("@\(username)")
    .toolbar {
      if let profile, edge.state != .isSelf, edge.state != .blocked, edge.state != .unknown {
        ToolbarItem(placement: .secondaryAction) {
          Button("Block", systemImage: "hand.raised", role: .destructive) { confirmBlock = true }
        }
        if let url = SocialLinks.profile(username: profile.user.username) {
          ToolbarItem(placement: .secondaryAction) { ShareLink(item: url) }
        }
      }
    }
    .confirmationDialog("Block \(profile?.user.shownName ?? username)?", isPresented: $confirmBlock, titleVisibility: .visible) {
      Button("Block", role: .destructive) { block() }
    } message: {
      Text("You stop following each other, and neither of you can see the other's profile or trips.")
    }
    .errorAlert($error)
    // A follow, an approval or a block changes what is visible: the profile
    // (can_view, counts) and then the trips are read again.
    .task(id: edge) { await load() }
  }

  /// What a visible profile shows below the counts: the showcase, trips and top places.
  @ViewBuilder private func profileContent(_ profile: Loci_Social_GetPublicProfileResponse) -> some View {
    if !profile.showcase.isEmpty {
      Section {
        ShowcaseRow(showcase: profile.showcase)
        NavigationLink(value: AppRoute.achievements(userID: edge.state == .isSelf ? "" : profile.user.id, name: profile.user.shownName)) {
          Text("All achievements").font(.lociCaption(15))
        }
      } header: {
        Text("Achievements")
      }
      .listRowBackground(Color.lociCard)
    }

    Section("Trips") {
      if trips.isEmpty {
        Text(emptyTrips).font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      }
      ForEach(trips, id: \.id) { FriendTripRow(trip: $0, showsOwner: false) }
    }
    .listRowBackground(Color.lociCard)

    if seesRankings {
      ForEach(RankingGroups.byCity(rankings.places), id: \.city) { group in
        RankedListSection(title: "Their top places · \(group.city)", places: group.places)
      }
      .listRowBackground(Color.lociCard)
    }
  }

  /// Rankings are friends-only on the server too; asking as a stranger is a 403.
  private var seesRankings: Bool { edge.isFriend || edge.state == .isSelf }

  private var emptyTrips: String {
    seesRankings ? "No shared trips yet." : "No public trips. Friends (people who follow each other) see the trips shared with friends."
  }

  private func subtitle(_ profile: Loci_Social_GetPublicProfileResponse) -> String {
    var parts = ["@\(profile.user.username)"]
    if !profile.user.homeCity.isEmpty { parts.append(profile.user.homeCity) }
    if profile.hasMemberSince {
      parts.append("On Loci since \(profile.memberSince.date.formatted(.dateTime.month(.wide).year()))")
    }
    return parts.joined(separator: " · ")
  }

  /// The profile, then what it lets the caller see. Setting `edge` from the
  /// answer re-runs the task; `loadedEdge` makes that second run a no-op.
  private func load() async {
    if profile != nil, loadedEdge == edge { return }
    guard edge.state != .blocked else {
      trips = []
      rankings.clear()
      return
    }
    do {
      let loaded = try await SocialAPI.profile(username: username)
      profile = loaded
      let fresh = FollowEdge(state: loaded.followState, followsYou: loaded.followsYou, relationship: loaded.relationship)
      loadedEdge = fresh
      edge = fresh
    } catch {
      if profile == nil { failure = error.userMessage } else if !error.isCancellation { self.error = error.userMessage }
      return
    }
    await loadTrips()
  }

  private func loadTrips() async {
    guard let profile, profile.canView else {
      trips = []
      rankings.clear()
      return
    }
    trips = (try? await SocialAPI.userTrips(userID: profile.user.id)) ?? []
    if seesRankings { await rankings.loadUser(id: profile.user.id) } else { rankings.clear() }
  }

  private func block() {
    guard let id = profile?.user.id else { return }
    Task {
      do {
        try await SocialAPI.block(userID: id)
        edge = FollowEdge(state: .blocked, followsYou: false)
      } catch { self.error = error.userMessage }
    }
  }
}

/// Cities, countries, trips shared and friends, as four figures.
/// Two by two at accessibility sizes, where four across would truncate.
struct TravelStatsRow: View {
  let stats: Loci_Social_ProfileStats

  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    if typeSize.isAccessibilitySize {
      Grid(horizontalSpacing: 12, verticalSpacing: 12) {
        GridRow {
          figure(stats.cities, "Cities")
          figure(stats.countries, "Countries")
        }
        GridRow {
          figure(stats.visibleTrips, "Trips")
          figure(stats.friends, "Friends")
        }
      }
    } else {
      HStack {
        figure(stats.cities, "Cities")
        figure(stats.countries, "Countries")
        figure(stats.visibleTrips, "Trips")
        figure(stats.friends, "Friends")
      }
    }
  }

  private func figure(_ value: Int32, _ label: LocalizedStringKey) -> some View {
    VStack(spacing: 2) {
      Text(value, format: .number).font(.lociDisplay(22)).foregroundStyle(Color.lociInk)
      Text(label).textCase(.uppercase).font(.lociCoord(9)).tracking(1.2).foregroundStyle(Color.lociMutedInk)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }
}

/// Followers, following and achievements: each opens its list when the
/// profile is visible to the caller.
struct FollowCountsRow: View {
  let user: Loci_Social_PublicUser
  let stats: Loci_Social_ProfileStats
  let linksOpen: Bool

  var body: some View {
    HStack {
      link(stats.followers, "Followers", AppRoute.follows(userID: user.id, name: user.shownName, followers: true))
      link(stats.following, "Following", AppRoute.follows(userID: user.id, name: user.shownName, followers: false))
      link(stats.achievements, "Achievements", AppRoute.achievements(userID: user.id, name: user.shownName))
    }
  }

  @ViewBuilder private func link(_ value: Int32, _ label: LocalizedStringKey, _ route: AppRoute) -> some View {
    let figure = VStack(spacing: 2) {
      Text(value, format: .number).font(.lociDisplay(20)).foregroundStyle(Color.lociInk)
      Text(label).textCase(.uppercase).font(.lociCoord(9)).tracking(1.2).foregroundStyle(Color.lociMutedInk)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
    if linksOpen {
      NavigationLink(value: route) { figure }.buttonStyle(.plain)
    } else {
      figure
    }
  }
}
