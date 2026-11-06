import LociConnectProto
import SwiftUI

// What a traveller with access needs should know about a place, and the walk
// between two stops. Every note says where it came from: a verified fact, open
// data (with its licence), a route check, or the model's estimate, which the
// traveller should confirm before relying on it.

extension Loci_Poi_AccessibilityNoteSeverity {
  var rank: Int {
    switch self {
    case .barrier: 3
    case .caution: 2
    case .info: 1
    default: 0
    }
  }

  var symbol: String {
    switch self {
    case .barrier: "xmark.octagon.fill"
    case .caution: "exclamationmark.triangle.fill"
    default: "checkmark.circle.fill"
    }
  }

  @MainActor var tint: Color {
    switch self {
    case .barrier: .lociDestructive
    case .caution: .lociLantern
    default: .lociSuccess
    }
  }

  /// Spoken before the note, so VoiceOver users get the colour's meaning.
  var spoken: String {
    switch self {
    case .barrier: String(localized: "Barrier")
    case .caution: String(localized: "Caution")
    default: String(localized: "Good to know")
    }
  }
}

extension Loci_Poi_AccessibilityNote {
  /// Where the claim comes from, in the traveller's terms.
  var sourceLabel: String {
    switch source {
    case .verifiedCrowd: String(localized: "Confirmed by travellers")
    case .openData:
      if hasSourceLicence, !sourceLicence.isEmpty { String(localized: "Open data · \(sourceLicence)") } else { String(localized: "Open data") }
    case .routed: String(localized: "Route check")
    default: String(localized: "AI estimate · check ahead")
    }
  }

  var isEstimate: Bool { source != .verifiedCrowd && source != .openData && source != .routed }

  var spokenSummary: String { "\(severity.spoken): \(text). \(sourceLabel)." }
}

extension Array where Element == Loci_Poi_AccessibilityNote {
  /// Most severe first; evidence before estimates within a severity.
  var bySeverity: [Loci_Poi_AccessibilityNote] {
    enumerated().sorted { a, b in
      if a.element.severity.rank != b.element.severity.rank { return a.element.severity.rank > b.element.severity.rank }
      if a.element.isEstimate != b.element.isEstimate { return !a.element.isEstimate }
      return a.offset < b.offset
    }.map(\.element)
  }
}

/// One note: severity icon, text, and its source underneath.
struct AccessibilityNoteRow: View {
  let note: Loci_Poi_AccessibilityNote

  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: 1) {
        Text(note.text).font(.lociCaption(13)).foregroundStyle(Color.lociInk).multilineTextAlignment(.leading)
        Text(note.sourceLabel).font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk)
      }
    } icon: {
      Image(systemName: note.severity.symbol).foregroundStyle(note.severity.tint)
    }.accessibilityElement(children: .ignore).accessibilityLabel(note.spokenSummary)
  }
}

/// A place's notes. `limit` keeps a card short; the detail sheet shows all.
struct AccessibilityNotesList: View {
  let notes: [Loci_Poi_AccessibilityNote]
  var limit: Int?

  var body: some View {
    let sorted = notes.bySeverity
    let shown = limit.map { Array(sorted.prefix($0)) } ?? sorted
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(shown.enumerated()), id: \.offset) { _, note in AccessibilityNoteRow(note: note) }
      if shown.count < sorted.count {
        Text("+\(sorted.count - shown.count) more access notes").font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk)
      }
    }
  }
}

/// The walk (or roll) from the previous stop, between two cards.
struct WalkingLegRow: View {
  let leg: Loci_Chat_WalkingLeg

  private var summary: String {
    var parts = [String(localized: "\(leg.durationMin) min"), Self.distance(leg.distanceM)]
    if leg.ascentM > 0 { parts.append(String(localized: "climbs \(leg.ascentM) m")) }
    return parts.joined(separator: " · ")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Image(systemName: leg.hasSuggestMode ? "car.fill" : "figure.walk").foregroundStyle(Color.lociMutedInk).accessibilityHidden(true)
        Text(summary).font(.lociCaption(12).weight(.semibold)).foregroundStyle(Color.lociInk)
        if !leg.routed { Text("route not checked").font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk) }
        Spacer(minLength: 0)
        if leg.hasSuggestMode {
          Text(leg.suggestMode == "transit" ? "Transit suggested" : "Taxi suggested").font(.lociCaption(11).weight(.semibold)).padding(.horizontal, 8)
            .padding(.vertical, 3).background(Color.lociMuted, in: Capsule())
        }
      }
      if !leg.notes.isEmpty { AccessibilityNotesList(notes: leg.notes, limit: 2) }
    }.padding(.leading, 12).padding(.vertical, 4).overlay(alignment: .leading) {
      Rectangle().fill(Color.lociBorder).frame(width: 2).accessibilityHidden(true)
    }.accessibilityElement(children: .combine).accessibilityLabel(spokenSummary)
  }

  private var spokenSummary: String {
    var parts = [String(localized: "Walk from the previous stop: \(summary)")]
    if !leg.routed { parts.append(String(localized: "Straight-line estimate, route not checked for steps or slopes")) }
    if leg.hasSuggestMode {
      parts.append(leg.suggestMode == "transit" ? String(localized: "Transit suggested") : String(localized: "Taxi suggested"))
    }
    parts += leg.notes.bySeverity.map(\.spokenSummary)
    return parts.joined(separator: ". ")
  }

  static func distance(_ metres: Int32) -> String {
    metres >= 1000
      ? String(localized: "\((Double(metres) / 1000).formatted(.number.precision(.fractionLength(1)))) km") : String(localized: "\(metres) m")
  }
}

extension Loci_Chat_AccessibleRoutePayload {
  /// The leg that ends at a stop, matched the way the server names stops: the
  /// POI id, or the name when the place has none.
  func leg(arrivingAt stop: Loci_Poi_POIDetailedInfo) -> Loci_Chat_WalkingLeg? {
    legs.first { $0.toPoiID == (stop.id.isEmpty ? stop.name : stop.id) }
  }
}
