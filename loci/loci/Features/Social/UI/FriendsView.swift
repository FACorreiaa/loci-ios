import LociConnectProto
import SwiftUI

/// Friends (web: /friends): what friends are sharing, who they are, requests
/// waiting on you, and ways to add people — username search, contacts and
/// an invite link.
struct FriendsView: View {
  enum Tab: String, CaseIterable, Identifiable {
    case trips = "Trips"
    case friends = "Friends"
    case requests = "Requests"

    var id: Self { self }
  }

  @State private var tab = Tab.trips
  @State private var feed: [Loci_Trip_TripDraft]?
  @State private var friends: [Loci_Social_Friend] = []
  @State private var incoming: [Loci_Social_FriendRequest] = []
  @State private var outgoing: [Loci_Social_FriendRequest] = []
  @State private var query = ""
  @State private var results: [SearchHit] = []
  @State private var showsInvite = false
  @State private var showsPhone = false
  @State private var error: String?

  struct SearchHit: Identifiable {
    var id: String { user.id }
    let user: Loci_Social_PublicUser
    var relationship: Relationship
  }

  var body: some View {
    List {
      if isSearching {
        searchResults
      } else {
        browsing
      }
    }
    .settingsStyle("Friends")
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

  private var isSearching: Bool { query.trimmingCharacters(in: .whitespaces).count >= 2 }

  // MARK: Sections

  @ViewBuilder private var browsing: some View {
    Section {
      Picker("Show", selection: $tab) {
        ForEach(Tab.allCases) { tab in
          Text(label(for: tab)).tag(tab)
        }
      }
      .pickerStyle(.segmented)
    }
    .listRowBackground(Color.clear)
    .listRowInsets(EdgeInsets())

    switch tab {
    case .trips: tripsSection
    case .friends: friendsSection
    case .requests: requestsSection
    }
    addSection
  }

  private func label(for tab: Tab) -> String {
    tab == .requests && !incoming.isEmpty ? "Requests (\(incoming.count))" : tab.rawValue
  }

  @ViewBuilder private var tripsSection: some View {
    Section {
      if let feed {
        if feed.isEmpty {
          Text("No shared trips yet. When a friend shares a trip with friends or publicly, it shows up here.")
            .font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
        }
        ForEach(feed, id: \.id) { FriendTripRow(trip: $0) }
      } else {
        ProgressView()
      }
    }
    .listRowBackground(Color.lociCard)
  }

  @ViewBuilder private var friendsSection: some View {
    Section {
      if friends.isEmpty {
        Text("No friends yet. Send your invite link to someone you travel with.").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      }
      ForEach(friends, id: \.user.id) { friend in
        NavigationLink { UserProfileView(username: friend.user.username) } label: {
          PersonRow(user: friend.user) { EmptyView() }
        }
      }
    }
    .listRowBackground(Color.lociCard)
  }

  @ViewBuilder private var requestsSection: some View {
    Section("Waiting on you") {
      if incoming.isEmpty { Text("No pending requests.").font(.lociCaption()).foregroundStyle(Color.lociMutedInk) }
      ForEach(incoming, id: \.id) { request in
        PersonRow(user: request.from) {
          HStack(spacing: 6) {
            Button("Accept") { respond(request, accept: true) }.buttonStyle(.borderedProminent).tint(.lociCoralFill)
            Button("Decline") { respond(request, accept: false) }.buttonStyle(.bordered)
          }
          .controlSize(.small)
        }
      }
    }
    .listRowBackground(Color.lociCard)
    if !outgoing.isEmpty {
      Section("Sent") {
        ForEach(outgoing, id: \.id) { request in
          PersonRow(user: request.to) {
            Button("Cancel") { cancel(request) }.buttonStyle(.bordered).controlSize(.small)
          }
        }
      }
      .listRowBackground(Color.lociCard)
    }
  }

  private var addSection: some View {
    Section {
      NavigationLink { ContactMatchView() } label: { Label("From your contacts", systemImage: "person.crop.rectangle.stack") }
      if FacebookConnect.isAvailable {
        NavigationLink { FacebookFriendsView() } label: { Label("From Facebook", systemImage: "person.2.badge.key") }
      }
      Button("Share your invite link", systemImage: "qrcode") { showsInvite = true }
      Button("Let friends find you by number", systemImage: "phone.badge.checkmark") { showsPhone = true }
    } header: {
      Text("Add friends")
    } footer: {
      Text("Instagram, X or WhatsApp: share your invite link there. Opening it makes you friends.")
    }
    .listRowBackground(Color.lociCard)
  }

  @ViewBuilder private var searchResults: some View {
    Section {
      if results.isEmpty { Text("Nobody by that username.").font(.lociCaption()).foregroundStyle(Color.lociMutedInk) }
      ForEach($results) { $hit in
        NavigationLink { UserProfileView(username: hit.user.username) } label: {
          PersonRow(user: hit.user) {
            RelationshipButton(
              user: hit.user,
              relationship: $hit.relationship,
              outgoingRequestID: outgoing.first { $0.to.id == hit.user.id }?.id
            )
          }
        }
      }
    }
    .listRowBackground(Color.lociCard)
  }

  // MARK: Loading

  private func load() async {
    async let feedTask = SocialAPI.friendTrips()
    async let friendsTask = SocialAPI.friends()
    async let incomingTask = SocialAPI.requests(incoming: true)
    async let outgoingTask = SocialAPI.requests(incoming: false)
    do {
      let loaded = try await (feedTask, friendsTask, incomingTask, outgoingTask)
      feed = loaded.0
      friends = loaded.1
      incoming = loaded.2
      outgoing = loaded.3
    } catch {
      if feed == nil { feed = [] }
      self.error = error.userMessage
    }
  }

  private func search() async {
    let text = query.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
    guard text.count >= 2 else {
      results = []
      return
    }
    try? await Task.sleep(for: .milliseconds(300))
    guard !Task.isCancelled else { return }
    results = ((try? await SocialAPI.search(text)) ?? []).map { SearchHit(user: $0.user, relationship: Relationship($0.relationship)) }
  }

  private func respond(_ request: Loci_Social_FriendRequest, accept: Bool) {
    Task {
      do {
        try await SocialAPI.respond(requestID: request.id, accept: accept)
        if accept { Analytics.capture(.friendAdded, ["via": "request"]) }
        await load()
      } catch { self.error = error.userMessage }
    }
  }

  private func cancel(_ request: Loci_Social_FriendRequest) {
    Task {
      do {
        try await SocialAPI.cancel(requestID: request.id)
        await load()
      } catch { self.error = error.userMessage }
    }
  }
}
