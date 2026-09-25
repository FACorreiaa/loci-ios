import Foundation
import LociConnectProto

/// How a field's answer is built: one token, several tokens (each filed as
/// its own claim), or the canonical opening-hours string.
nonisolated enum FieldKind: Sendable { case single, multi, structured }

/// One answer a scout can pick. `token` is the wire value; `label` is free to change.
nonisolated struct FieldOption: Hashable, Sendable {
  let token: String
  let label: String
}

nonisolated struct FieldVocabulary: Sendable {
  let kind: FieldKind
  let question: String
  let options: [FieldOption]
  /// Cap on selections for a multi-select field.
  var maxSelections: Int?
}

/// The canonical vocabulary a field report is written in, ported one to one
/// from web's `lib/place-facts/vocabulary.ts` and mirrored in Go at
/// `loci-connect-server/internal/domain/placeintel/values.go`.
///
/// The server corroborates two claims only when their values are the same
/// string, so every answer is a token from a fixed list, normalised to one
/// spelling before it is sent. A token on only one side is either a question
/// nobody can answer or an answer the server rejects.
nonisolated enum PlaceFactVocabulary {
  /// "I checked, and none of these apply": it cannot sit beside the things it
  /// denies. The server rejects that pairing too.
  static let exclusiveToken = "none"

  /// The fields a scout can be asked about, in the order they are offered (web: CONTRIBUTABLE_FIELDS).
  static let contributableFields: [Loci_Place_PlaceFactField] = [
    .openingHours, .priceLevel, .accessibility, .dietary, .crowdLevel, .noiseLevel, .childFriendly, .dogFriendly, .vibe,
  ]

  static func vocabulary(for field: Loci_Place_PlaceFactField) -> FieldVocabulary? {
    if field == .openingHours { return FieldVocabulary(kind: .structured, question: "When is it open?", options: []) }
    return singleChoice(field) ?? multiChoice(field)
  }

  private static func singleChoice(_ field: Loci_Place_PlaceFactField) -> FieldVocabulary? {
    switch field {
    case .priceLevel:
      FieldVocabulary(
        kind: .single,
        question: "What does a typical visit cost?",
        options: [
          FieldOption(token: "budget", label: "€ Budget"), FieldOption(token: "moderate", label: "€€ Moderate"),
          FieldOption(token: "pricey", label: "€€€ Pricey"), FieldOption(token: "splurge", label: "€€€€ Splurge"),
        ]
      )
    case .crowdLevel:
      FieldVocabulary(
        kind: .single,
        question: "How busy was it?",
        options: [
          FieldOption(token: "quiet", label: "Quiet"), FieldOption(token: "moderate", label: "Moderate"), FieldOption(token: "busy", label: "Busy"),
          FieldOption(token: "packed", label: "Packed"),
        ]
      )
    case .noiseLevel:
      FieldVocabulary(
        kind: .single,
        question: "How loud was it?",
        options: [
          FieldOption(token: "quiet", label: "You can whisper"), FieldOption(token: "conversational", label: "Normal talk"),
          FieldOption(token: "lively", label: "Raise your voice"), FieldOption(token: "loud", label: "Can't hear"),
        ]
      )
    case .childFriendly:
      FieldVocabulary(
        kind: .single,
        question: "Would you bring children?",
        options: [
          FieldOption(token: "yes", label: "Yes"), FieldOption(token: "limited", label: "Some limits"), FieldOption(token: "no", label: "Not really"),
        ]
      )
    case .dogFriendly:
      FieldVocabulary(
        kind: .single,
        question: "Are dogs welcome?",
        options: [
          FieldOption(token: "yes", label: "Yes, inside"), FieldOption(token: "outdoor_only", label: "Outdoor seating only"),
          FieldOption(token: "no", label: "No dogs"),
        ]
      )
    default: nil
    }
  }

  private static func multiChoice(_ field: Loci_Place_PlaceFactField) -> FieldVocabulary? {
    switch field {
    case .accessibility:
      FieldVocabulary(
        kind: .multi,
        question: "What did you see that helps with access?",
        options: [
          FieldOption(token: "step_free", label: "Step-free entrance"), FieldOption(token: "accessible_wc", label: "Accessible toilet"),
          FieldOption(token: "lift", label: "Lift"), FieldOption(token: "wide_doors", label: "Wide doorways"),
          FieldOption(token: "tactile", label: "Tactile guidance"), FieldOption(token: exclusiveToken, label: "None of these"),
        ]
      )
    case .dietary:
      FieldVocabulary(
        kind: .multi,
        question: "Which diets are properly catered for?",
        options: [
          FieldOption(token: "vegetarian", label: "Vegetarian"), FieldOption(token: "vegan", label: "Vegan"),
          FieldOption(token: "gluten_free", label: "Gluten free"), FieldOption(token: "halal", label: "Halal"),
          FieldOption(token: "kosher", label: "Kosher"), FieldOption(token: exclusiveToken, label: "None of these"),
        ]
      )
    case .vibe:
      // Each tag is filed and corroborated on its own; the cap only keeps the answer considered.
      FieldVocabulary(
        kind: .multi,
        question: "How did it feel? Pick up to three.",
        options: [
          FieldOption(token: "cosy", label: "Cosy"), FieldOption(token: "lively", label: "Lively"), FieldOption(token: "romantic", label: "Romantic"),
          FieldOption(token: "touristy", label: "Touristy"), FieldOption(token: "local", label: "Local"), FieldOption(token: "quiet", label: "Quiet"),
          FieldOption(token: "work_friendly", label: "Good for working"), FieldOption(token: "outdoorsy", label: "Outdoorsy"),
        ],
        maxSelections: 3
      )
    default: nil
    }
  }

  /// web: fieldQuestion.
  static func question(_ field: Loci_Place_PlaceFactField) -> String { vocabulary(for: field)?.question ?? "What is true right now?" }

  /// web: fieldLabel ("Opening Hours", "Child Friendly"), built from the wire name.
  static func label(_ field: Loci_Place_PlaceFactField) -> String {
    wireName(field).replacingOccurrences(of: "PLACE_FACT_FIELD_", with: "").lowercased().split(separator: "_").map {
      $0.prefix(1).uppercased() + $0.dropFirst()
    }.joined(separator: " ")
  }

  /// The proto enum's name, as web's analytics sends it (`field` on `place_claim_submitted`).
  static func wireName(_ field: Loci_Place_PlaceFactField) -> String {
    switch field {
    case .openingHours: "PLACE_FACT_FIELD_OPENING_HOURS"
    case .priceLevel: "PLACE_FACT_FIELD_PRICE_LEVEL"
    case .accessibility: "PLACE_FACT_FIELD_ACCESSIBILITY"
    case .dietary: "PLACE_FACT_FIELD_DIETARY"
    case .crowdLevel: "PLACE_FACT_FIELD_CROWD_LEVEL"
    case .noiseLevel: "PLACE_FACT_FIELD_NOISE_LEVEL"
    case .childFriendly: "PLACE_FACT_FIELD_CHILD_FRIENDLY"
    case .dogFriendly: "PLACE_FACT_FIELD_DOG_FRIENDLY"
    case .vibe: "PLACE_FACT_FIELD_VIBE"
    default: "PLACE_FACT_FIELD_UNSPECIFIED"
    }
  }

  /// What a stored fact reads as: the option's label, or the value itself
  /// (opening hours, or a token this build does not know).
  static func displayValue(_ field: Loci_Place_PlaceFactField, _ value: String) -> String {
    vocabulary(for: field)?.options.first { $0.token == value.lowercased() }?.label ?? value
  }

  /// web: claimValuesFor. One claim per answer, so each corroborates on its
  /// own; cleaned (trimmed, lowercased, de-duplicated, empties dropped) and
  /// sorted, so a selection always produces the same claims in the same order.
  /// A single-answer field keeps only the first.
  static func claimValues(_ field: Loci_Place_PlaceFactField, tokens: [String]) -> [String] {
    let cleaned = Set(tokens.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).filter { !$0.isEmpty }.sorted()
    guard let first = cleaned.first else { return [] }
    return vocabulary(for: field)?.kind == .single ? [first] : cleaned
  }

  /// web: FieldPicker. A tap on `token` given the current selection.
  /// - single: picks it, or clears it when it was already picked.
  /// - multi: toggles it; "none" on its own clears the rest, anything else
  ///   clears "none"; past the cap the oldest pick drops (a picker that goes
  ///   dead under the finger reads as broken).
  static func toggle(_ token: String, in selection: [String], field: Loci_Place_PlaceFactField) -> [String] {
    guard let vocabulary = vocabulary(for: field) else { return selection }
    switch vocabulary.kind {
    case .structured: return selection
    case .single: return selection.first == token ? [] : [token]
    case .multi:
      if selection.contains(token) { return selection.filter { $0 != token && $0 != exclusiveToken } }
      if token == exclusiveToken { return [exclusiveToken] }
      let next = selection.filter { $0 != exclusiveToken } + [token]
      if let cap = vocabulary.maxSelections, next.count > cap { return Array(next.suffix(cap)) }
      return next
    }
  }
}
