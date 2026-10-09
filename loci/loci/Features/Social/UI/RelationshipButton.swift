import LociConnectProto
import SwiftUI

/// The one control for "what am I to this person" (web: RelationshipButton).
/// Accepting an incoming request is the same call as sending one: the server
/// turns crossing requests into a friendship.
struct RelationshipButton: View {
  let user: Loci_Social_PublicUser
  @Binding var relationship: Relationship
  /// Needed to cancel a sent request; nil when the caller doesn't know it.
  var outgoingRequestID: String?

  @State private var isBusy = false
  @State private var confirmRemove = false
  @State private var error: String?

  var body: some View {
    Group {
      switch relationship {
      case .notConnected:
        Button("Add friend", systemImage: "person.badge.plus") { run(sendRequest) }
          .buttonStyle(.borderedProminent).tint(.lociCoralFill)
      case .incoming:
        Button("Accept", systemImage: "checkmark") { run(sendRequest) }
          .buttonStyle(.borderedProminent).tint(.lociCoralFill)
      case .requested:
        Button("Requested") { run(cancelRequest) }.buttonStyle(.bordered).disabled(outgoingRequestID == nil)
      case .friends:
        Button("Friends", systemImage: "person.fill.checkmark") { confirmRemove = true }.buttonStyle(.bordered)
      case .blocked:
        Button("Unblock") { run { try await SocialAPI.unblock(userID: user.id); relationship = .notConnected } }.buttonStyle(.bordered)
      case .isSelf, .unknown:
        EmptyView()
      }
    }
    .tint(.lociCoral)
    .disabled(isBusy)
    .confirmationDialog("Remove \(user.shownName) as a friend?", isPresented: $confirmRemove, titleVisibility: .visible) {
      Button("Remove friend", role: .destructive) { run { try await SocialAPI.remove(userID: user.id); relationship = .notConnected } }
    }
    .errorAlert($error)
  }

  /// Also accepts: the server befriends when the other side already asked.
  private func sendRequest() async throws {
    relationship = try await SocialAPI.sendRequest(userID: user.id)
    if relationship == .friends { Analytics.capture(.friendAdded, ["via": "profile"]) }
  }

  private func cancelRequest() async throws {
    guard let outgoingRequestID else { return }
    try await SocialAPI.cancel(requestID: outgoingRequestID)
    relationship = .notConnected
  }

  private func run(_ action: @escaping @MainActor () async throws -> Void) {
    isBusy = true
    Task {
      defer { isBusy = false }
      do { try await action() } catch { self.error = error.userMessage }
    }
  }
}
