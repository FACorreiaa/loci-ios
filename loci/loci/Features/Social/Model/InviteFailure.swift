import Foundation

/// Words for an invite link that could not be opened or accepted. The server
/// answers NotFound ("not found") alike for an unknown, expired or rotated code,
/// an inviter who is gone, and a blocked pair, and its other messages are
/// written for logs ("that is you"), so none of them is shown as it is.
nonisolated enum InviteFailure: Equatable, Sendable {
  /// NotFound: the link no longer leads anywhere.
  case expired
  /// No network, or the server is out.
  case offline
  /// Unauthenticated, after the refresh-and-retry already failed.
  case signedOut
  case other

  init(_ error: any Error) {
    switch error as? APIError {
    case .notFound: self = .expired
    case .network: self = .offline
    case .unauthorized: self = .signedOut
    default: self = .other
    }
  }

  enum Action: Sendable { case open, accept }

  /// The headline for the screen.
  func title(for action: Action) -> String {
    switch self {
    case .expired: "This invite has expired."
    case .offline: "Couldn't reach Loci. Check your connection and try again."
    case .signedOut: "Sign in again to accept this invite."
    case .other: action == .open ? "Could not open the invite." : "Could not accept the invite."
    }
  }

  /// The line under the headline when the invite could not be opened.
  var hint: String {
    switch self {
    case .expired: "Ask your friend for a new link."
    case .offline, .signedOut, .other: "Try opening the link again in a moment."
    }
  }
}
