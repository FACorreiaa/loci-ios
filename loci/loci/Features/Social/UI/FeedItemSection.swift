import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// One thing someone you follow did (web: FeedItemCard): an achievement, a
/// new city, a finished or shared trip, with cheers. A section of its own, so
/// the profile link, the trip link and the cheer are separate rows (two links
/// in one List row both fire).
struct FeedItemSection: View {
  @Binding var item: Loci_Social_FeedItem

  var body: some View {
    Section {
      NavigationLink(value: AppRoute.user(username: item.actor.username)) {
        HStack(alignment: .top, spacing: 10) {
          UserAvatar(user: item.actor, size: 36)
          VStack(alignment: .leading, spacing: 2) {
            Text("\(Text(item.actor.shownName).font(.lociHeadline(15))) \(item.headline)")
              .font(.lociCaption(15)).foregroundStyle(Color.lociInk)
              .fixedSize(horizontal: false, vertical: true)
            Text(item.createdAt.date.formatted(.relative(presentation: .named))).font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
          }
          Spacer(minLength: 0)
          detailBadge
        }
        .padding(.vertical, 4)
      }
      if case .trip(let trip) = item.detail, !trip.tripID.isEmpty {
        NavigationLink(value: AppRoute.sharedTrip(.tripID(trip.tripID))) {
          Label(tripLine(trip), systemImage: "map").font(.lociCaption(14)).foregroundStyle(Color.lociForest)
        }
      }
      HStack {
        CheerButton(item: $item)
        if let line = item.cheerLine { Text(line).font(.lociCaption()).foregroundStyle(Color.lociMutedInk).lineLimit(1) }
        Spacer()
      }
    }
    .listRowBackground(Color.lociCard)
  }

  @ViewBuilder private var detailBadge: some View {
    switch item.detail {
    case .achievement(let a): MedallionView(a, size: 40)
    case .city: Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(Color.lociCoral).accessibilityHidden(true)
    case .trip: Image(systemName: "figure.walk.circle.fill").font(.title2).foregroundStyle(Color.lociForest).accessibilityHidden(true)
    case nil: EmptyView()
    }
  }

  private func tripLine(_ trip: Loci_Social_FeedTrip) -> String {
    var parts = [trip.cityName]
    if trip.days > 0 { parts.append(trip.days == 1 ? "1 day" : "\(trip.days) days") }
    return parts.filter { !$0.isEmpty }.joined(separator: " · ")
  }
}

/// Cheers an item, at once on screen; the server's count replaces the guess,
/// and a failure puts the old one back.
struct CheerButton: View {
  @Binding var item: Loci_Social_FeedItem
  @State private var isBusy = false
  @State private var error: String?

  var body: some View {
    Button {
      toggle()
    } label: {
      Label(item.cheeredByMe ? "Cheered" : "Cheer", systemImage: item.cheeredByMe ? "hands.clap.fill" : "hands.clap")
        .font(.lociCaption(14))
    }
    .buttonStyle(.bordered)
    .tint(item.cheeredByMe ? .lociCoral : .lociMutedInk)
    .disabled(isBusy)
    .sensoryFeedback(.impact(weight: .light), trigger: item.cheeredByMe) { _, on in on }
    .accessibilityValue(item.cheerCount > 0 ? "\(item.cheerCount)" : "")
    .errorAlert($error)
  }

  private func toggle() {
    let before = item
    let on = !item.cheeredByMe
    item = item.cheered(on)
    isBusy = true
    Task {
      defer { isBusy = false }
      do {
        let response = try await SocialAPI.cheer(itemID: before.id, on)
        item.cheerCount = response.cheerCount
        item.cheeredByMe = response.cheeredByMe
        if on { Analytics.capture(.cheer, ["kind": before.detailKind]) }
      } catch {
        item = before
        self.error = error.userMessage
      }
    }
  }
}
