import LociConnectProto
import SwiftUI

/// People (web: /friends): what the people you follow are doing, the trips
/// they share, your followers and who you follow, requests waiting on you,
/// and ways to find people — username search, contacts and an invite link.
struct FriendsView: View {
  enum Tab: String, CaseIterable, Identifiable {
    case feed = "Feed"
    case trips = "Trips"
    case followers = "Followers"
    case following = "Following"
    case requests = "Requests"

    var id: Self { self }
  }

  @State private var tab: Tab
  @State private var feed: [Loci_Social_FeedItem]?
  @State private var feedToken = ""
  /// The feed fails on its own (it has its own kill switch); the other tabs still load.
  @State private var feedError: String?
  @State private var trips: [Loci_Trip_TripDraft]?
  @State private var followers: [FollowRow] = []
  @State private var following: [FollowRow] = []
  @State private var incoming: [Loci_Social_FollowRequestEntry] = []
  @State private var outgoing: [Loci_Social_FollowRequestEntry] = []
  @State private var query = ""
  @State private var results: [FollowRow] = []
  @State private var searching = false
  @State private var searchError: String?
  @State private var showsInvite = false
  @State private var showsPhone = false
  @State private var error: String?

  init(tab: Tab = .feed) {
    _tab = State(initialValue: tab)
  }

  var body: some View {
    List {
      if isSearching {
        searchResults
      } else {
        browsing
      }
    }
    .settingsStyle("People")
    .searchable(text: $query, prompt: "Find by @username")
    .task(id: query) { await search() }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Invite", systemImage: "qrcode") { showsInvite = true }
      }
    }
    .sheet(isPresented: $showsInvite) { InviteSheet() }
    .sheet(isPresented: $showsPhone) { PhoneVerifySheet() }
    .refreshable { await load() }
    .errorAlert($error)
    .task { await load() }
  }

  /// The username typed, without spaces or the "@".
  private var searchText: String { query.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "") }
  private var isSearching: Bool { searchText.count >= 2 }

  // MARK: Sections

  @ViewBuilder private var browsing: some View {
    // Chips, not a segmented control: five segments truncate on a phone.
    Section {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(Tab.allCases) { item in
            Button(label(for: item)) { tab = item }
              .font(.lociCaption(14))
              .buttonStyle(.bordered)
              .tint(tab == item ? .lociCoral : .lociMutedInk)
              .accessibilityAddTraits(tab == item ? .isSelected : [])
          }
        }
      }
    }
    .listRowBackground(Color.clear)
    .listRowInsets(EdgeInsets())

    switch tab {
    case .feed: feedSection
    case .trips: tripsSection
    case .followers: followersSection
    case .following: followingSection
    case .requests: requestsSection
    }
    addSection
  }

  private func label(for tab: Tab) -> String {
    tab == .requests && !incoming.isEmpty ? "Requests (\(incoming.count))" : tab.rawValue
  }

  @ViewBuilder private var feedSection: some View {
    if let feed, feedError == nil, !feed.isEmpty {
      ForEach(Binding(get: { self.feed ?? [] }, set: { self.feed = $0 }), id: \.id) { $item in
        FeedItemSection(item: $item)
          .onAppear { if item.id == feed.last?.id { Task { await loadMoreFeed() } } }
      }
    } else {
      Section {
        if let feedError {
          Text(feedError).font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
        } else if feed != nil {
          Text("Nothing yet. Follow people to see their new cities, finished trips and achievements here.")
            .font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
        } else {
          ProgressView()
        }
      }
      .listRowBackground(Color.lociCard)
    }
  }

  @ViewBuilder private var tripsSection: some View {
    Section {
      if let trips {
        if trips.isEmpty {
          Text("No shared trips yet. Public trips from people you follow, and friends-only trips from your friends, show up here.")
            .font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
        }
        ForEach(trips, id: \.id) { FriendTripRow(trip: $0) }
      } else {
        ProgressView()
      }
    }
    .listRowBackground(Color.lociCard)
  }

  @ViewBuilder private var followersSection: some View {
    Section {
      if followers.isEmpty {
        Text("No followers yet. Send your invite link to someone you travel with.").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      }
      ForEach($followers) { $row in
        FollowRowView(row: $row, via: "followers")
          .swipeActions {
            Button("Remove", role: .destructive) { removeFollower(row) }
          }
      }
    } footer: {
      if !followers.isEmpty { Text("Following each other makes you friends: friends see the trips you share with friends.") }
    }
    .listRowBackground(Color.lociCard)
  }

  @ViewBuilder private var followingSection: some View {
    Section {
      if following.isEmpty {
        Text("You don't follow anyone yet. Search by username above, or find people from your contacts.")
          .font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      }
      ForEach($following) { FollowRowView(row: $0, via: "following") }
    }
    .listRowBackground(Color.lociCard)
  }

  @ViewBuilder private var requestsSection: some View {
    Section("Waiting on you") {
      if incoming.isEmpty { Text("No pending requests.").font(.lociCaption()).foregroundStyle(Color.lociMutedInk) }
      ForEach(incoming, id: \.id) { request in
        PersonRow(user: request.from) {
          HStack(spacing: 6) {
            Button("Approve") { respond(request, approve: true) }.buttonStyle(.borderedProminent).tint(.lociCoralFill)
            Button("Decline") { respond(request, approve: false) }.buttonStyle(.bordered)
          }
        }
      }
    }
    .listRowBackground(Color.lociCard)
    if !outgoing.isEmpty {
      Section("Sent") {
        ForEach(outgoing, id: \.id) { request in
          PersonRow(user: request.to) {
            Button("Cancel") { cancel(request) }.buttonStyle(.bordered)
          }
        }
      }
      .listRowBackground(Color.lociCard)
    }
    Section {
      AccountPrivacyToggle()
    }
    .listRowBackground(Color.lociCard)
  }

  private var addSection: some View {
    Section {
      NavigationLink(value: AppRoute.contactMatch) { Label("From your contacts", systemImage: "person.crop.rectangle.stack") }
      if FacebookConnect.isAvailable {
        NavigationLink(value: AppRoute.facebookFriends) { Label("From Facebook", systemImage: "person.2.badge.key") }
      }
      Button("Share your invite link", systemImage: "qrcode") { showsInvite = true }
      Button("Let people find you by number", systemImage: "phone.badge.checkmark") { showsPhone = true }
    } header: {
      Text("Find people")
    } footer: {
      Text("Instagram, X or WhatsApp: share your invite link there. Opening it makes you friends.")
    }
    .listRowBackground(Color.lociCard)
  }

  @ViewBuilder private var searchResults: some View {
    Section {
      if let searchError {
        Text(searchError).font(.lociCaption()).foregroundStyle(Color.lociDestructive)
      } else if results.isEmpty {
        if searching {
          ProgressView().frame(maxWidth: .infinity)
        } else {
          Text("Nobody by that username.").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
        }
      }
      ForEach($results) { FollowRowView(row: $0, via: "search") }
    }
    .listRowBackground(Color.lociCard)
  }

  // MARK: Loading

  private func load() async {
    async let feedLoad: Void = loadFeed()
    async let tripsTask = SocialAPI.friendTrips()
    async let followersTask = SocialAPI.followers()
    async let followingTask = SocialAPI.following()
    async let incomingTask = SocialAPI.followRequests(incoming: true)
    async let outgoingTask = SocialAPI.followRequests(incoming: false)
    do {
      let loaded = try await (tripsTask, followersTask, followingTask, incomingTask, outgoingTask)
      trips = loaded.0
      followers = loaded.1.entries.map(FollowRow.init)
      following = loaded.2.entries.map(FollowRow.init)
      incoming = loaded.3
      outgoing = loaded.4
    } catch {
      if !error.isCancellation {
        if trips == nil { trips = [] }
        self.error = error.userMessage
      }
    }
    await feedLoad
  }

  private func loadFeed() async {
    do {
      let page = try await SocialAPI.feed()
      feed = page.items
      feedToken = page.nextPageToken
      feedError = nil
    } catch {
      guard !error.isCancellation else { return }
      if feed == nil { feedError = error.userMessage }
    }
  }

  private func loadMoreFeed() async {
    guard !feedToken.isEmpty else { return }
    let token = feedToken
    feedToken = ""
    do {
      let page = try await SocialAPI.feed(pageToken: token)
      let known = Set((feed ?? []).map(\.id))
      feed = (feed ?? []) + page.items.filter { !known.contains($0.id) }
      feedToken = page.nextPageToken
    } catch {
      feedToken = token
      if !error.isCancellation { self.error = error.userMessage }
    }
  }

  /// Debounced; a failure says so rather than reading as "nobody found".
  private func search() async {
    let text = searchText
    searchError = nil
    guard text.count >= 2 else {
      results = []
      searching = false
      return
    }
    searching = true
    try? await Task.sleep(for: .milliseconds(300))
    guard !Task.isCancelled else { return }
    do {
      results = try await SocialAPI.search(text).map(FollowRow.init)
    } catch {
      guard !error.isCancellation else { return }
      results = []
      searchError = error.userMessage
    }
    searching = false
  }

  private func respond(_ request: Loci_Social_FollowRequestEntry, approve: Bool) {
    Task {
      do {
        try await SocialAPI.respondFollow(requestID: request.id, approve: approve)
        await load()
      } catch { self.error = error.userMessage }
    }
  }

  private func cancel(_ request: Loci_Social_FollowRequestEntry) {
    Task {
      do {
        try await SocialAPI.cancelFollow(requestID: request.id)
        await load()
      } catch { self.error = error.userMessage }
    }
  }

  private func removeFollower(_ row: FollowRow) {
    Task {
      do {
        try await SocialAPI.removeFollower(userID: row.user.id)
        followers.removeAll { $0.id == row.id }
      } catch { self.error = error.userMessage }
    }
  }
}

/// A person in a list with the caller's follow edge to them.
struct FollowRow: Identifiable {
  var id: String { user.id }
  let user: Loci_Social_PublicUser
  var edge: FollowEdge

  init(_ entry: Loci_Social_FollowEntry) {
    user = entry.user
    edge = FollowEdge(state: entry.followState, followsYou: entry.followsYou)
  }

  init(_ hit: Loci_Social_UserResult) {
    user = hit.user
    edge = FollowEdge(state: hit.followState, followsYou: hit.followsYou, relationship: hit.relationship)
  }
}

/// The person (a link to their profile) and, beside it, the follow button:
/// beside, not inside, so a tap on the button never opens the profile.
struct FollowRowView: View {
  @Binding var row: FollowRow
  var via: String

  var body: some View {
    HStack(spacing: 8) {
      NavigationLink(value: AppRoute.user(username: row.user.username)) {
        PersonRow(user: row.user) { EmptyView() }
      }
      FollowButton(user: row.user, edge: $row.edge, via: via)
    }
  }
}
