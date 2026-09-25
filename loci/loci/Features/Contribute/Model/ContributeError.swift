import Connect
import Foundation

/// What the server said when a report, a new place or a confirmation was
/// refused, turned into words a scout can act on. The server's messages are
/// written for logs ("\"Foo\" is already on the guide (uuid)", "could not place
/// \"Foo\" in a city: …") and web shows them as they are; here each refusal
/// gets one plain sentence, and the ones that can never succeed on a retry
/// say so instead of offering one.
nonisolated struct ContributeError: LocalizedError, Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    /// AlreadyExists on SubmitPlace: the guide has it; search instead.
    case alreadyOnGuide(name: String?)
    /// NotFound: the place the report was about is gone.
    case unknownPlace
    /// InvalidArgument: the server could not use what was typed (city resolution, mostly).
    case invalidInput(String)
    /// FailedPrecondition: right request, wrong moment (no coordinates yet, own submission).
    case notYet(String)
    /// Unimplemented: contributions are off on this server.
    case unavailable
    /// Unavailable / DeadlineExceeded: no network, or the server is out.
    case offline
    case other
  }

  enum Action: Sendable { case report, addPlace, confirm }

  let kind: Kind
  let serverMessage: String

  /// A retry can only help when nothing about the request was wrong.
  var canRetry: Bool {
    switch kind {
    case .alreadyOnGuide, .unknownPlace, .invalidInput, .notYet, .unavailable: false
    case .offline, .other: true
    }
  }

  var errorDescription: String? { serverMessage }

  init(kind: Kind, serverMessage: String) {
    self.kind = kind
    self.serverMessage = serverMessage
  }

  init(_ error: ConnectError?, fallback: String) {
    let message = error?.message ?? fallback
    serverMessage = message
    switch error?.code {
    case .alreadyExists: kind = .alreadyOnGuide(name: Self.quotedName(in: message))
    case .notFound: kind = .unknownPlace
    case .invalidArgument: kind = .invalidInput(message)
    case .failedPrecondition: kind = .notYet(message)
    case .unimplemented: kind = .unavailable
    case .unavailable, .deadlineExceeded: kind = .offline
    default: kind = .other
    }
  }

  /// One sentence for the screen, by what the scout was doing.
  func message(for action: Action) -> String {
    switch kind {
    case .alreadyOnGuide(let name):
      if let name { return "“\(name)” is already on the guide. Search for it above." }
      return "That place is already on the guide. Search for it above."
    case .unknownPlace: return "That place isn't on the guide any more."
    case .invalidInput:
      return action == .addPlace ? "We couldn't place that in a city. Check the city name." : "Check what you entered and try again."
    case .notYet(let reason): return Self.sentence(reason)
    case .unavailable: return "Contributions are switched off right now. Try later."
    case .offline: return "You're offline. Try again when you're back online."
    case .other:
      switch action {
      case .report: return "Could not file the report. Try again."
      case .addPlace: return "Could not add this place. Try again."
      case .confirm: return "That did not go through. Try again."
      }
    }
  }

  /// The wording for any error a store catches: a `ContributeError` by its
  /// kind, anything else by the action's own fallback. Never raw text.
  static func message(from error: any Error, for action: Action) -> String {
    (error as? ContributeError ?? ContributeError(kind: .other, serverMessage: "")).message(for: action)
  }

  /// `"Café Central" is already on the guide (…)` → `Café Central`.
  private static func quotedName(in message: String) -> String? {
    guard let match = message.firstMatch(of: #/"([^"]+)"/#) else { return nil }
    let name = String(match.1).trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? nil : name
  }

  /// The server's reason, capitalised and with a full stop, so it reads as a sentence.
  private static func sentence(_ reason: String) -> String {
    let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first else { return "That can't be confirmed yet." }
    let body = first.uppercased() + trimmed.dropFirst()
    return body.hasSuffix(".") ? body : body + "."
  }
}
