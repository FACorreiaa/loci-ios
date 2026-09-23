import Foundation

/// What Loci's avatar shows (apps/_reviews/muse-chat-contract.md, "Avatar states
/// + status copy"). There is no working art: `working` is the idle art plus a ring.
nonisolated enum MuseMood: Equatable, Sendable {
  case idle
  case listening
  case working
  case celebrating
}

/// The header's avatar mood and status line, derived from a search.
///
/// `resolve` is pure so every state can be tested without a screen. The two
/// states that only last a moment after a search ends (celebrating, hit a snag)
/// come in as a `Flash` that the screen holds and clears on a timer.
nonisolated struct MuseActivity: Equatable, Sendable {
  var mood: MuseMood
  var status: String

  /// A short-lived state after a search ends.
  enum Flash: Equatable, Sendable {
    case celebrating(places: Int)
    case snag

    var duration: Duration {
      switch self {
      case .celebrating: MuseActivity.celebrationDuration
      case .snag: MuseActivity.snagDuration
      }
    }
  }

  static let ready = MuseActivity(mood: .idle, status: "Ready")
  static let celebrationDuration: Duration = .milliseconds(1200)
  static let snagDuration: Duration = .seconds(3)
  /// The contract's limit for a tool/progress label.
  static let maxStageLength = 32

  /// Precedence: a running search, then a flash, then the composer, then Ready.
  /// A running search wins over the composer because it says more.
  static func resolve(
    status: SearchState.Status?,
    hasText: Bool = false,
    progressStage: String? = nil,
    flash: Flash? = nil,
    isListening: Bool = false
  ) -> MuseActivity {
    switch status {
    case .streaming:
      if let stage = stagePhrase(progressStage) { return MuseActivity(mood: .working, status: "is \(stage)") }
      return MuseActivity(mood: .working, status: hasText ? "is writing" : "is thinking")
    case .detached:
      return MuseActivity(mood: .working, status: "is still working — you can leave")
    case .idle, .completed, .completedWithError, .failed, nil:
      break
    }
    switch flash {
    case .celebrating(let places):
      return MuseActivity(mood: .celebrating, status: places == 1 ? "found 1 place" : places > 1 ? "found \(places) places" : "is done")
    case .snag:
      return MuseActivity(mood: .idle, status: "hit a snag")
    case nil:
      break
    }
    return isListening ? MuseActivity(mood: .listening, status: "is listening") : .ready
  }

  /// The same, read off a search. Places landing count as writing too.
  static func resolve(_ state: SearchState?, flash: Flash? = nil, isListening: Bool = false) -> MuseActivity {
    resolve(
      status: state?.status,
      hasText: state.map { !$0.text.isEmpty || $0.hasResult } ?? false,
      progressStage: state?.progressStage,
      flash: flash,
      isListening: isListening
    )
  }

  /// The flash a status change earns: only a search that was running and
  /// then ended. Opening a finished search, or pressing Stop, earns nothing.
  static func flash(from old: SearchState.Status?, to new: SearchState.Status?, places: Int) -> Flash? {
    guard old == .streaming || old == .detached else { return nil }
    switch new {
    case .completed: return .celebrating(places: places)
    // Places arrived before the error: a partial win, the rail shows the snag.
    case .completedWithError: return places > 0 ? .celebrating(places: places) : .snag
    case .failed(let message): return message == SearchState.stoppedMessage ? nil : .snag
    default: return nil
    }
  }

  /// The server's `ProgressPayload.stage` as the verb phrase after "is".
  /// Takes any string: machine names (`intent_classified`, `progress`) and
  /// blanks give nil so the status falls back to thinking/writing; a leading
  /// "is " and trailing dots are dropped; a capital first letter is lowered
  /// unless the word is an acronym; anything over 32 characters is cut with "…".
  static func stagePhrase(_ raw: String?) -> String? {
    guard var phrase = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !phrase.isEmpty else { return nil }
    if phrase.contains("_") || phrase.lowercased() == "progress" { return nil }
    if phrase.lowercased().hasPrefix("is ") { phrase = String(phrase.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
    while let last = phrase.last, last == "." || last == "…" { phrase.removeLast() }
    phrase = phrase.trimmingCharacters(in: .whitespaces)
    guard let first = phrase.first else { return nil }
    let firstWord = phrase.prefix { !$0.isWhitespace }
    let isAcronym = firstWord.count > 1 && firstWord.allSatisfy { $0.isUppercase || $0.isNumber }
    if first.isUppercase, !isAcronym { phrase = first.lowercased() + phrase.dropFirst() }
    if phrase.count > maxStageLength {
      phrase = String(phrase.prefix(maxStageLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
    return phrase
  }
}
