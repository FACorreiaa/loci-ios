import LociConnectProto
import SwiftUI

/// Someone else's trip, read-only (web: /t/:code and /friends/trips/:id): who
/// made it, the days, and "Save to my trips", which copies it as a private
/// trip of your own and opens it.
struct SharedTripView: View {
  let source: SharedTripSource

  @State private var trip: Loci_Trip_TripDraft?
  @State private var failure: String?
  @State private var isCopying = false
  @State private var copiedTripID: String?
  @State private var error: String?

  var body: some View {
    List {
      if let trip {
        Section {
          TripHero(trip: trip).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
        if trip.hasOwner {
          Section {
            NavigationLink { UserProfileView(username: trip.owner.username) } label: {
              PersonRow(user: trip.owner, subtitle: "Shared · \(TripVisibility(trip.visibility).label)") { EmptyView() }
            }
            .disabled(trip.owner.username.isEmpty)
          }
          .listRowBackground(Color.lociCard)
        }
        ForEach(trip.days, id: \.id) { day in
          Section {
            ForEach(day.stops, id: \.id) { stop in
              StopRow(stop: stop, color: LociTheme.dayColor(Int(day.dayNumber)), isEditing: false) { _ in }
            }
          } header: {
            Text(day.cityName.isEmpty || day.cityName == trip.cityName ? "Day \(day.dayNumber)" : "Day \(day.dayNumber) · \(day.cityName)")
          }
          .listRowBackground(Color.lociCard)
        }
      } else if let failure {
        ContentUnavailableView(failure, systemImage: "lock", description: Text("It may be private now, or the link was turned off."))
          .listRowBackground(Color.clear)
      } else {
        ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
      }
    }
    .settingsStyle(trip?.title ?? "Shared trip")
    .toolbar {
      if trip != nil {
        ToolbarItem(placement: .primaryAction) {
          Button("Save to my trips", systemImage: "plus.square.on.square") { copy() }.disabled(isCopying)
        }
        if let shareURL {
          ToolbarItem(placement: .secondaryAction) { ShareLink(item: shareURL) }
        }
      }
    }
    .navigationDestination(item: $copiedTripID) { TripEditorView(tripID: $0) }
    .errorAlert($error)
    .task { await load() }
  }

  /// The link to pass on: only a trip opened by its link has one to give.
  private var shareURL: URL? {
    guard case .code(let code) = source else { return nil }
    return SocialLinks.sharedTrip(code: code)
  }

  private func load() async {
    do {
      switch source {
      case .code(let code): trip = try await SocialAPI.sharedTrip(code: code)
      case .tripID(let id): trip = try await SocialAPI.friendTrip(id: id)
      }
    } catch {
      failure = error.userMessage
    }
  }

  private func copy() {
    isCopying = true
    Task {
      defer { isCopying = false }
      do {
        copiedTripID = try await SocialAPI.copy(source)
        Analytics.capture(.tripCopied, ["via": shareURL == nil ? "friend" : "link"])
      } catch {
        self.error = error.userMessage
      }
    }
  }
}

/// A trip in the friends feed or on a profile.
struct FriendTripRow: View {
  let trip: Loci_Trip_TripDraft
  var showsOwner = true

  var body: some View {
    NavigationLink {
      SharedTripView(source: trip.shareCode.isEmpty ? .tripID(trip.id) : .code(trip.shareCode))
    } label: {
      HStack(spacing: 12) {
        if showsOwner, trip.hasOwner { UserAvatar(user: trip.owner, size: 32) }
        VStack(alignment: .leading, spacing: 3) {
          Text(trip.title.isEmpty ? trip.cityName : trip.title).font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
          Text(summary).font(.lociCaption()).foregroundStyle(Color.lociMutedInk).lineLimit(1)
        }
      }
    }
  }

  private var summary: String {
    let stops = trip.days.reduce(0) { $0 + $1.stops.count }
    let owner = showsOwner && trip.hasOwner ? "\(trip.owner.shownName) · " : ""
    let city = trip.cityName.isEmpty ? "" : "\(trip.cityName) · "
    return "\(owner)\(city)\(trip.days.count) day\(trip.days.count == 1 ? "" : "s") · \(stops) stop\(stops == 1 ? "" : "s")"
  }
}
