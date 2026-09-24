import Foundation

/// The taste vocabulary a City Pack can be cut for (web: lib/bundles/themes.ts).
///
/// It mirrors `Themes` in the server's `internal/domain/bundle/forge/seeds.go`,
/// and the catalog filters on these exact raw values, so adding one means
/// changing the server, web and here.
nonisolated enum PackTheme: String, CaseIterable, Identifiable, Sendable {
  case food
  case art
  case outdoors
  case architecture
  case nightlife
  case family
  case localLife = "local_life"

  var id: String { rawValue }

  /// web: PACK_THEME_META[id].label
  var label: String {
    switch self {
    case .food: "Food & wine"
    case .art: "Art & music"
    case .outdoors: "Outdoors"
    case .architecture: "Architecture"
    case .nightlife: "Nightlife"
    case .family: "Family"
    case .localLife: "Local life"
    }
  }

  /// web: PACK_THEME_META[id].emoji
  var emoji: String {
    switch self {
    case .food: "🍷"
    case .art: "🎨"
    case .outdoors: "🥾"
    case .architecture: "🏛️"
    case .nightlife: "🌃"
    case .family: "🧸"
    case .localLife: "🚋"
    }
  }

  /// web: themeLabel. An id this build does not know shows as itself rather than blank.
  static func label(for id: String) -> String { PackTheme(rawValue: id)?.label ?? id }
}

/// Months as a pack describes them (web: lib/bundles/themes.ts `monthsLabel`).
nonisolated enum PackMonths {
  static let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

  static func name(_ month: Int) -> String { (1...12).contains(month) ? names[month - 1] : "" }

  /// Consecutive months collapse into a range, and a set that wraps the year
  /// end (Nov, Dec, Jan, Feb) reads as one range, "Nov–Feb", not two.
  static func label(_ months: [Int]) -> String {
    let sorted = Set(months).filter { (1...12).contains($0) }.sorted()
    guard let first = sorted.first else { return "Any time" }
    if sorted.count == 12 { return "All year" }

    var runs: [[Int]] = []
    var run = [first]
    for month in sorted.dropFirst() {
      if let last = run.last, month == last + 1 {
        run.append(month)
      } else {
        runs.append(run)
        run = [month]
      }
    }
    runs.append(run)

    // December is adjacent to January: join the last run onto the first.
    if runs.count > 1, sorted.contains(1), sorted.contains(12) {
      let head = runs.removeFirst()
      let tail = runs.removeLast()
      runs.insert(tail + head, at: 0)
    }

    return runs.map { run in
      guard let start = run.first, let end = run.last else { return "" }
      return run.count == 1 ? name(start) : "\(name(start))–\(name(end))"
    }.joined(separator: ", ")
  }

  /// The month chips before "All months": this month and the next two, wrapping
  /// past December (web: packs/index.tsx `visibleMonths`).
  static func upcoming(from current: Int) -> [Int] {
    let month = (1...12).contains(current) ? current : 1
    return [month, month % 12 + 1, (month + 1) % 12 + 1]
  }
}
