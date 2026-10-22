import LociConnectProto
import SwiftUI

/// A trip invite link opened in the app (web: /j/:code): the trip's outline
/// and who is going, then Join trip, which lands in the trip as a co-planner.
/// Links need the tabs, so the caller is signed in by the time this shows.
struct TripInviteView: View {
  let code: String

  @State private var preview: Loci_Trip_TripInvitePreview?
  @State private var loadError: String?
  @State private var isJoining = false
  @State private var joinedTripID: String?
  @State private var error: String?

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        if let preview {
          content(preview)
        } else if let loadError {
          ContentUnavailableView("Invite not found", systemImage: "link.badge.plus", description: Text(loadError))
        } else {
          ProgressView()
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity)
    }
    .defaultScrollAnchor(.center, for: .alignment)
    .scrollBounceBehavior(.basedOnSize)
    .background(Color.lociPaper.ignoresSafeArea())
    .navigationTitle("Trip invite").navigationBarTitleDisplayMode(.inline)
    .navigationDestination(item: $joinedTripID) { TripEditorView(tripID: $0) }
    .errorAlert($error)
    .task {
      Analytics.capture(.tripInviteOpened, ["signed_in": true])
      do { preview = try await TripMembersAPI.preview(code: code) } catch { loadError = error.localizedDescription }
    }
  }

  @ViewBuilder private func content(_ p: Loci_Trip_TripInvitePreview) -> some View {
    let owner = p.hasOwner ? p.owner.shownName : "A friend"
    Text("\(owner) invited you to \(p.role == .viewer ? "follow" : "plan") a trip")
      .font(.lociCaption(15)).foregroundStyle(Color.lociMutedInk).multilineTextAlignment(.center)
    Text(p.title).font(.lociDisplay(26)).foregroundStyle(Color.lociInk).multilineTextAlignment(.center)
    HStack(spacing: 12) {
      if !p.cityName.isEmpty { Label(p.cityName, systemImage: "mappin") }
      Label(dates(p), systemImage: "calendar")
    }
    .font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
    HStack(spacing: -10) {
      ForEach(Array(p.members.prefix(6).enumerated()), id: \.offset) { _, member in
        UserAvatar(user: member.user, size: 44).overlay(Circle().stroke(Color.lociPaper, lineWidth: 2))
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(p.members.count == 1 ? "\(owner) so far" : "\(p.members.count) going")
    Text(p.members.count == 1 ? "\(owner) so far" : "\(p.members.count) going")
      .font(.lociCaption()).foregroundStyle(Color.lociMutedInk)

    if p.alreadyMember {
      Button("Open the trip") { joinedTripID = p.tripID }
        .buttonStyle(.borderedProminent).tint(.lociCoralFill).controlSize(.large)
    } else if !p.joinable {
      Text("This invite has expired. Ask \(owner) for a new link.")
        .font(.lociCaption()).foregroundStyle(Color.lociMutedInk).multilineTextAlignment(.center)
    } else {
      Button(isJoining ? "Joining…" : "Join trip") { join() }
        .buttonStyle(.borderedProminent).tint(.lociCoralFill).controlSize(.large).disabled(isJoining)
    }
  }

  private func dates(_ p: Loci_Trip_TripInvitePreview) -> String {
    if p.hasStartDate, p.hasEndDate, let range = TripInviteDates.range(p.startDate, p.endDate) { return range }
    return p.dayCount == 1 ? "1 day" : "\(p.dayCount) days"
  }

  private func join() {
    isJoining = true
    Task {
      defer { isJoining = false }
      do { joinedTripID = try await TripMembersAPI.accept(code: code) } catch { self.error = error.localizedDescription }
    }
  }
}

/// "12 Sep – 15 Sep" from a trip's planned date keys.
@MainActor enum TripInviteDates {
  static func range(_ start: String, _ end: String) -> String? {
    guard let from = CalendarMath.parseDateKey(start), let to = CalendarMath.parseDateKey(end) else { return nil }
    let style = Date.FormatStyle().day().month(.abbreviated)
    return from == to ? from.formatted(style) : "\(from.formatted(style)) – \(to.formatted(style))"
  }
}
