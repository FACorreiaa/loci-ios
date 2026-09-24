import Foundation

/// Star labels and colour bands (web: ReviewForm's `getRatingText`,
/// ReviewCard's `getRatingColor`).
nonisolated enum ReviewRating {
  static let range = 1...5

  /// web: 1 Terrible … 5 Excellent; nothing for "no rating yet".
  static func label(_ rating: Int) -> String {
    switch rating {
    case 1: "Terrible"
    case 2: "Poor"
    case 3: "Average"
    case 4: "Good"
    case 5: "Excellent"
    default: ""
    }
  }

  enum Tone: Equatable, Sendable {
    /// ≥ 4 (web: green)
    case high
    /// ≥ 3 (web: yellow)
    case middle
    /// below 3 (web: red)
    case low
  }

  static func tone(_ rating: Double) -> Tone {
    if rating >= 4 { return .high }
    if rating >= 3 { return .middle }
    return .low
  }

  /// A server double as whole stars in range (the server only stores whole ones).
  static func clamp(_ rating: Double) -> Int {
    guard rating.isFinite else { return range.lowerBound }
    return min(max(Int(rating.rounded()), range.lowerBound), range.upperBound)
  }
}

/// What the write/edit sheet holds (web: ReviewForm's signals, minus photos
/// and travel type: there is no upload RPC and the proto has no such field).
nonisolated struct ReviewForm: Equatable, Sendable {
  static let titleLimit = 100
  static let contentMinimum = 10
  static let contentLimit = 1000

  /// 0 until a star is tapped.
  var rating = 0
  var title = ""
  var content = ""
  var visitDate: Date?

  init(rating: Int = 0, title: String = "", content: String = "", visitDate: Date? = nil) {
    self.rating = rating
    self.title = title
    self.content = content
    self.visitDate = visitDate
  }

  init(_ review: LociReview) { self.init(rating: review.rating, title: review.title, content: review.content, visitDate: review.visitDate) }

  enum Issue: Equatable, Sendable {
    case noRating, noContent, contentTooShort, contentTooLong, titleTooLong

    /// web's copy where it has one.
    var message: String {
      switch self {
      case .noRating: "Please select a rating"
      case .noContent: "Please write a review"
      case .contentTooShort: "Review must be at least \(ReviewForm.contentMinimum) characters"
      case .contentTooLong: "Keep it under \(ReviewForm.contentLimit) characters"
      case .titleTooLong: "Keep the title under \(ReviewForm.titleLimit) characters"
      }
    }
  }

  var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
  var trimmedContent: String { content.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// Every rule the form breaks, in the order the sheet shows them. Web only
  /// checks the minimum; the limits here are enforced as well, since the
  /// fields clamp what is typed and a pasted text could still slip past.
  var issues: [Issue] {
    var issues: [Issue] = []
    if !ReviewRating.range.contains(rating) { issues.append(.noRating) }
    if trimmedTitle.count > Self.titleLimit { issues.append(.titleTooLong) }
    let count = trimmedContent.count
    if count == 0 {
      issues.append(.noContent)
    } else if count < Self.contentMinimum {
      issues.append(.contentTooShort)
    } else if count > Self.contentLimit {
      issues.append(.contentTooLong)
    }
    return issues
  }

  var isValid: Bool { issues.isEmpty }

  /// The content counter, "42/1000" (web's), counted on what will be sent.
  var contentCounter: String { "\(trimmedContent.count)/\(Self.contentLimit)" }
  var titleCounter: String { "\(title.count)/\(Self.titleLimit)" }

  /// What a field keeps of a typed or pasted value.
  static func clampTitle(_ value: String) -> String { String(value.prefix(titleLimit)) }
  static func clampContent(_ value: String) -> String { String(value.prefix(contentLimit)) }
}

/// Long reviews fold (web: ReviewCard's `truncateContent`, 200 characters).
nonisolated enum ReviewText {
  static let foldLength = 200

  static func needsFold(_ content: String, limit: Int = foldLength) -> Bool { content.count > limit }

  /// The first `limit` characters and an ellipsis; the whole text when it fits.
  static func folded(_ content: String, limit: Int = foldLength) -> String {
    guard needsFold(content, limit: limit) else { return content }
    let head = content.prefix(limit)
    return head.trimmingCharacters(in: .whitespacesAndNewlines) + "\u{2026}"
  }
}

/// The caller's helpful vote on one review, with its count. Tapping flips it
/// at once; the server's `new_helpful_count` settles it; a failure puts the
/// previous state back. The server has no "did I vote" field, so a review
/// starts unvoted on each load (see the doc's server gaps).
nonisolated struct HelpfulVote: Equatable, Sendable {
  var isLiked: Bool
  var count: Int

  init(isLiked: Bool = false, count: Int) {
    self.isLiked = isLiked
    self.count = max(0, count)
  }

  /// The optimistic state after a tap.
  func toggled() -> HelpfulVote { HelpfulVote(isLiked: !isLiked, count: isLiked ? count - 1 : count + 1) }

  /// The `is_like` a tap sends: true adds the vote, false takes it back.
  var tapSendsLike: Bool { !isLiked }

  /// The server's count wins; the vote stays as tapped.
  func settled(serverCount: Int) -> HelpfulVote { HelpfulVote(isLiked: isLiked, count: serverCount) }
}
