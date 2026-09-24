import Foundation

/// Does a message read like something to keep doing, not something to answer
/// once? Only decides whether to *offer* a standing-task card; the server's
/// ProposeWatch does the understanding, and the user still confirms.
///
/// Two ways in:
/// - an explicit ask to be told later: "remind me", "let me know when",
///   "keep an eye on", "notify me", … ("tell me when the museum opens" is a
///   question, so bare "tell me when" is not one of them)
/// - a recurrence ("every morning", "daily", "each Monday", "every 3 hours")
///   together with a telling verb ("tell me", "send me", "check", "update me").
///
/// A recurrence alone is not enough: "3 days in Rome, gelato every day" is a
/// trip, and so is "show me a plan with a museum every day".
nonisolated enum StandingRequest {
  static func matches(_ text: String) -> Bool {
    let lowered = " " + text.lowercased().replacingOccurrences(of: "’", with: "'") + " "
    let normalized = lowered.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    if explicitCues.contains(where: normalized.contains) { return true }
    return hasRecurrence(normalized) && tellingVerbs.contains(where: normalized.contains)
  }

  private static let explicitCues = [
    "remind me", "let me know when", "notify me", "alert me", "ping me",
    "keep an eye on", "keep me posted", "keep me updated", "watch for", "watch out for",
    "tell me whenever", "message me when",
  ]

  private static let tellingVerbs = [
    " tell me", " send me", " check ", " update me", " let me know", " brief me",
  ]

  private static let recurrencePattern = [
    #"\b(every|each) ((other|single) )?(\d+ )?"#,
    #"(day|morning|afternoon|evening|night|week|weekend|month|hour|hours|days|weeks"#,
    #"|monday|tuesday|wednesday|thursday|friday|saturday|sunday)s?\b"#,
    #"|\b(daily|weekly|monthly|hourly|nightly)\b"#,
  ].joined()

  private static func hasRecurrence(_ text: String) -> Bool {
    text.range(of: recurrencePattern, options: .regularExpression) != nil
  }
}
