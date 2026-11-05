import Foundation

/// Turns streamed text into pieces to read aloud
/// (web: loci-client/src/lib/assistant/sentences.ts).
///
/// Speech starts on the first complete sentence rather than on the whole answer,
/// so a reply that takes a few seconds to arrive starts being heard in one.
nonisolated struct SentenceChunker: Sendable {
  /// How long a piece of text may wait for a sentence to end before it is spoken.
  static let maxPending = 240

  /// A full stop after a number, a lone capital or a title is rarely the end of
  /// a sentence: "3.5 stars", "J. Smith", "St. George".
  private static let sentenceEnd = try! NSRegularExpression(  // swiftlint:disable:this force_try
    pattern: #"(?<![0-9])(?<!\b[A-Z])(?<!\b(?:St|Dr|Mr|Mrs|Ms|Av|Sr|Sra))[.!?…]+["')\]]*\s+|\n+"#
  )

  private var pending = ""

  /// Adds text and returns any sentences it completed.
  mutating func push(_ text: String) -> [String] {
    pending += text
    var out: [String] = []
    let whole = pending as NSString
    var start = 0
    let everything = NSRange(location: 0, length: whole.length)
    for match in Self.sentenceEnd.matches(in: pending, range: everything) {
      let end = match.range.location + match.range.length
      let piece = whole.substring(with: NSRange(location: start, length: end - start))
      out.append(piece.trimmingCharacters(in: .whitespacesAndNewlines))
      start = end
    }
    pending = whole.substring(from: start)
    while pending.count > Self.maxPending {
      let window = pending.prefix(Self.maxPending + 1)
      guard let cut = window.lastIndex(of: " "), cut > pending.startIndex else { break }
      out.append(String(pending[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines))
      pending = String(pending[pending.index(after: cut)...])
    }
    return out.map(Self.speakable).filter { !$0.isEmpty }
  }

  /// Whatever is left when the answer ends.
  mutating func flush() -> [String] {
    let rest = Self.speakable(pending)
    pending = ""
    return rest.isEmpty ? [] : [rest]
  }

  /// Strips what a voice would read out as punctuation.
  static func speakable(_ text: String) -> String {
    text
      .replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
      .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"[*_`#>]+"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
