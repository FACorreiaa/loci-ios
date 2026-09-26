import LociConnectProto
import SwiftUI

/// Someone's travel profile (web: /u/:username): who they are, where they've
/// been, and the trips you may see.
struct UserProfileView: View {
  let username: String

  @State private var profile: Loci_Social_GetPublicProfileResponse?
  @State private var relationship = Relationship.unknown
  @State private var trips: [Loci_Trip_TripDraft] = []
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
            RelationshipButton(user: profile.user, relationship: $relationship)
          }
          .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .listRowBackground(Color.lociCard)

        Section { TravelStatsRow(stats: profile.stats) }.listRowBackground(Color.lociCard)

        Section("Trips") {
          if trips.isEmpty {
            Text(emptyTrips).font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
          }
          ForEach(trips, id: \.id) { FriendTripRow(trip: $0, showsOwner: false) }
        }
        .listRowBackground(Color.lociCard)
      } else if let failure {
        ContentUnavailableView(failure, systemImage: "person.crop.circle.badge.questionmark").listRowBackground(Color.clear)
      } else {
        ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
      }
    }
    .settingsStyle("@\(username)")
    .toolbar {
      if let profile, relationship != .isSelf, relationship != .blocked, relationship != .unknown {
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
      Text("You stop being friends, and neither of you can see the other's profile or trips.")
    }
    .errorAlert($error)
    .task { await load() }
    .onChange(of: relationship) { Task { await loadTrips() } }
  }

  private var emptyTrips: String {
    relationship == .friends || relationship == .isSelf ? "No shared trips yet." : "No public trips. Friends see the trips shared with friends."
  }

  private func subtitle(_ profile: Loci_Social_GetPublicProfileResponse) -> String {
    var parts = ["@\(profile.user.username)"]
    if !profile.user.homeCity.isEmpty { parts.append(profile.user.homeCity) }
    if profile.hasMemberSince {
      parts.append("On Loci since \(profile.memberSince.date.formatted(.dateTime.month(.wide).year()))")
    }
    return parts.joined(separator: " · ")
  }

  private func load() async {
    do {
      let loaded = try await SocialAPI.profile(username: username)
      profile = loaded
      relationship = Relationship(loaded.relationship)
      await loadTrips()
    } catch {
      failure = error.userMessage
    }
  }

  private func loadTrips() async {
    guard let id = profile?.user.id else { return }
    trips = (try? await SocialAPI.userTrips(userID: id)) ?? []
  }

  private func block() {
    guard let id = profile?.user.id else { return }
    Task {
      do {
        try await SocialAPI.block(userID: id)
        relationship = .blocked
      } catch { self.error = error.userMessage }
    }
  }
}

/// Cities, countries, trips shared and friends, as four figures.
struct TravelStatsRow: View {
  let stats: Loci_Social_ProfileStats

  var body: some View {
    HStack {
      figure(stats.cities, "Cities")
      figure(stats.countries, "Countries")
      figure(stats.visibleTrips, "Trips")
      figure(stats.friends, "Friends")
    }
  }

  private func figure(_ value: Int32, _ label: String) -> some View {
    VStack(spacing: 2) {
      Text("\(value)").font(.lociDisplay(22)).foregroundStyle(Color.lociInk)
      Text(label.uppercased()).font(.lociCoord(9)).tracking(1.2).foregroundStyle(Color.lociMutedInk)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }
}
