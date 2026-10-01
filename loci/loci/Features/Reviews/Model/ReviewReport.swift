import Connect
import Foundation

/// Reporting someone else's review (web: REPORT_REASONS in lib/reviews/model.ts).
/// The server accepts exactly these reason values; anything else is InvalidArgument.
nonisolated enum ReviewReport {
  enum Reason: String, CaseIterable, Sendable {
    case spam, inappropriate, fake, offensive, other

    var value: String { rawValue }

    var label: String {
      switch self {
      case .spam: "Spam or advertising"
      case .inappropriate: "Inappropriate"
      case .fake: "Not a real visit"
      case .offensive: "Offensive"
      case .other: "Something else"
      }
    }
  }

  static let reasons = Reason.allCases

  /// The refusals a reporter gets in plain words instead of the server's
  /// message (which, for your own review, talks about votes). Nil for any
  /// other answer, which the usual error mapping words.
  static func refusal(_ code: Code?) -> String? {
    switch code {
    case .some(.permissionDenied): "You can't report your own review."
    case .some(.failedPrecondition): "This review can't be reported right now."
    case .some(.unimplemented): "Reporting isn't available on the server yet."
    default: nil
    }
  }
}
