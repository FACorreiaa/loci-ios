import LociConnectProto
import SwiftUI

/// Who is on the trip (web: TripMembersBar). The owner gets Plan together,
/// which opens the trip's invite link in the share sheet; a member gets Leave
/// trip.
struct TripMembersSection: View {
  let trip: Loci_Trip_TripDraft
  let isOwner: Bool
  var onLeft: () -> Void = {}

  @State private var inviting = false
  @State private var confirmLeave = false
  @State private var error: String?

  var body: some View {
    Section {
      HStack(spacing: 12) {
        if trip.members.isEmpty {
          Label("Just you so far", systemImage: "person.2").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
        } else {
          HStack(spacing: -8) {
            ForEach(Array(trip.members.prefix(6).enumerated()), id: \.offset) { _, member in
              UserAvatar(user: member.user, size: 32).overlay(Circle().stroke(Color.lociPaper, lineWidth: 2))
            }
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(trip.members.map(\.user.shownName).joined(separator: ", "))
          Text("\(trip.members.count) going").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
        }
        Spacer()
        if isOwner {
          Button { inviting = true } label: { Label("Plan together", systemImage: "person.badge.plus") }
            .buttonStyle(.borderedProminent).tint(.lociCoralFill).controlSize(.small)
        } else {
          Button("Leave", role: .destructive) { confirmLeave = true }.controlSize(.small)
        }
      }
    }
    .sheet(isPresented: $inviting) { TripInviteSheet(trip: trip) }
    .confirmationDialog("Leave this trip?", isPresented: $confirmLeave, titleVisibility: .visible) {
      Button("Leave trip", role: .destructive) { leave() }
    } message: {
      Text("You'll need a new invite to join again.")
    }
    .errorAlert($error)
  }

  private func leave() {
    guard let me = AuthSessionManager.shared.currentUserID else { return }
    Task {
      do {
        try await TripMembersAPI.remove(tripID: trip.id, userID: me)
        onLeft()
      } catch { self.error = error.localizedDescription }
    }
  }
}

/// The trip's invite link, sent through the system share sheet. Anyone who
/// opens it joins as a co-planner; it works for 14 days.
struct TripInviteSheet: View {
  let trip: Loci_Trip_TripDraft

  @Environment(\.dismiss) private var dismiss
  @State private var invite: Loci_Trip_TripInvite?
  @State private var loadFailed = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        if let invite, let url = URL(string: invite.url) {
          Image(systemName: "person.2.fill").font(.system(size: 44)).foregroundStyle(Color.lociCoral)
          Text("Anyone who opens this link joins as a co-planner: they see the whole trip and can suggest changes. It works for 14 days.")
            .font(.lociCaption(15)).multilineTextAlignment(.center).foregroundStyle(Color.lociMutedInk)
          ShareLink(item: url, message: Text("Plan \(trip.title) with me on Loci")) {
            Label("Send invite", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent).tint(.lociCoralFill).controlSize(.large)
        } else if loadFailed {
          ContentUnavailableView {
            Label("Could not make an invite link", systemImage: "link.badge.plus")
          } description: {
            Text("Check your connection and try again.")
          } actions: {
            Button("Try again") { Task { await load() } }.buttonStyle(.borderedProminent).tint(.lociCoralFill)
          }
        } else {
          ProgressView()
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color.lociPaper.ignoresSafeArea())
      .navigationTitle("Plan together").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
      .task { await load() }
    }
    .presentationDetents([.medium])
  }

  private func load() async {
    loadFailed = false
    do { invite = try await TripMembersAPI.invite(tripID: trip.id) } catch { loadFailed = true }
  }
}
