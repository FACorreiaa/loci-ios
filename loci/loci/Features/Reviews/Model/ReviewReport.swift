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
}
