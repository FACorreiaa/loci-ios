import Foundation
import LociConnectProto

/// Which exports a plan gets, mirroring web's TripExportMenu. With plan
/// gating off (`PlanGating.enabled`, the default) every format exports for
/// every plan with no notice; the rules below apply once gating is on:
/// - Calendar (.ics) always works; a free plan on a multi-day trip gets Day 1
///   (the server trims it) and a note saying so.
/// - PDF is Pro-only once the trip is longer than one day.
/// - Markdown is Pro-only.
///
/// Copy is neutral on purpose: iOS never links to web pricing (App Store 3.1.1).
nonisolated enum TripExportGate {
  enum Decision: Equatable, Sendable {
    /// Export, then show `notice` if there is one.
    case export(notice: String?)
    /// Do not call the server; tell the traveller why.
    case locked(String)
  }

  static let formats: [Loci_Trip_ExportFormat] = [.ics, .pdf, .markdown]

  static func decide(_ format: Loci_Trip_ExportFormat, isPro: Bool, dayCount: Int, gating: Bool = PlanGating.enabled) -> Decision {
    let isPro = ProGate.entitled(isPro: isPro, gating: gating)
    switch format {
    case .ics:
      if !isPro, dayCount > 1 { return .export(notice: "Day-1 calendar works free. Pro includes every day in the .ics.") }
      return .export(notice: nil)
    case .pdf:
      if !isPro, dayCount > 1 { return .locked("The multi-day PDF is included with Pro.") }
      return .export(notice: nil)
    case .markdown:
      if !isPro { return .locked("Markdown export is included with Pro.") }
      return .export(notice: nil)
    default:
      return .locked("That export format isn't supported.")
    }
  }

  static func isLocked(_ format: Loci_Trip_ExportFormat, isPro: Bool, dayCount: Int, gating: Bool = PlanGating.enabled) -> Bool {
    if case .locked = decide(format, isPro: isPro, dayCount: dayCount, gating: gating) { return true }
    return false
  }

  static func label(_ format: Loci_Trip_ExportFormat) -> String {
    switch format {
    case .ics: "Calendar file (.ics)"
    case .pdf: "PDF"
    case .markdown: "Markdown (.md)"
    default: "Export"
    }
  }

  static func fileExtension(_ format: Loci_Trip_ExportFormat) -> String {
    switch format {
    case .pdf: "pdf"
    case .markdown: "md"
    default: "ics"
    }
  }

  /// web: ExportFormat[format].toLowerCase() → "ics" | "pdf" | "markdown"
  static func analyticsName(_ format: Loci_Trip_ExportFormat) -> String {
    switch format {
    case .ics: "ics"
    case .pdf: "pdf"
    case .markdown: "markdown"
    default: "unspecified"
    }
  }

  /// The server's filename when it sent a safe one, else "trip.<ext>". A path
  /// separator would write outside the temporary directory, so it is dropped.
  static func filename(serverName: String, format: Loci_Trip_ExportFormat) -> String {
    let base = serverName.split(separator: "/").last.map(String.init) ?? ""
    let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else { return "trip.\(fileExtension(format))" }
    return trimmed
  }
}
