import Foundation
import LociConnectProto

/// Pure checklist logic (web: components/trip/TripChecklists.tsx), kept apart
/// from the store so every rule has a test.
nonisolated enum TripChecklist {
  /// The server's cap per trip (ResourceExhausted past it).
  static let maxItems = 500
  static let maxTextLength = 300

  /// The dedupe key: the server stores dismissals lowercased and trimmed, so
  /// both sides are compared that way.
  static func key(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

  /// Suggestions not already on the packing list or waved away, case-insensitive,
  /// so the panel empties out as the traveller works through it (web: openSuggestions).
  static func openSuggestions(
    _ suggestions: [Loci_Trip_PackingSuggestion],
    items: [Loci_Trip_ChecklistItem],
    dismissed: [String]
  ) -> [Loci_Trip_PackingSuggestion] {
    let taken = Set(items.filter { $0.kind == .packing }.map { key($0.text) })
    let gone = Set(dismissed.map(key))
    var seen = Set<String>()
    return suggestions.filter { suggestion in
      let k = key(suggestion.text)
      guard !k.isEmpty, !taken.contains(k), !gone.contains(k) else { return false }
      return seen.insert(k).inserted
    }
  }

  /// One kind's items in display order: position, then text as a stable tiebreak.
  static func items(_ items: [Loci_Trip_ChecklistItem], kind: Loci_Trip_ChecklistItemKind) -> [Loci_Trip_ChecklistItem] {
    items.filter { $0.kind == kind }.sorted { ($0.position, $0.text, $0.id) < ($1.position, $1.text, $1.id) }
  }

  /// "2/5 packed", or nil for an empty list (web shows nothing then).
  static func packedSummary(_ items: [Loci_Trip_ChecklistItem]) -> String? {
    let packing = items.filter { $0.kind == .packing }
    guard !packing.isEmpty else { return nil }
    return "\(packing.filter(\.done).count)/\(packing.count) packed"
  }

  /// Whether a failed edit may put back what was there before: only while the
  /// item on screen is still the one that failed. A later edit to the same item
  /// that already landed is newer truth and must not be undone by an older
  /// failure arriving late.
  static func shouldRollBack(current: Loci_Trip_ChecklistItem?, failed: Loci_Trip_ChecklistItem) -> Bool {
    current == failed
  }

  /// The position after the last item of that kind.
  static func nextPosition(_ items: [Loci_Trip_ChecklistItem], kind: Loci_Trip_ChecklistItemKind) -> Int32 {
    (items.filter { $0.kind == kind }.map(\.position).max() ?? -1) + 1
  }

  /// A new item with a client UUID, so a retry of the same edit upserts the same row.
  static func makeItem(
    kind: Loci_Trip_ChecklistItemKind,
    text: String,
    position: Int32,
    amountMinor: Int64 = 0,
    currency: String = "",
    id: UUID = UUID()
  ) -> Loci_Trip_ChecklistItem? {
    let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTextLength))
    guard !trimmed.isEmpty else { return nil }
    var item = Loci_Trip_ChecklistItem()
    item.id = id.uuidString.lowercased()
    item.kind = kind
    item.text = trimmed
    item.position = position
    if kind == .expense {
      item.amountMinor = max(0, amountMinor)
      item.currency = currency
    }
    return item
  }

  // MARK: - Money

  /// The expense currency: the one already in use on this trip, else the
  /// phone's region, else EUR. Trips carry no currency of their own.
  static func defaultCurrency(_ items: [Loci_Trip_ChecklistItem], locale: Locale = .current) -> String {
    if let used = items.first(where: { $0.kind == .expense && isCurrencyCode($0.currency) })?.currency { return used }
    if let regional = locale.currency?.identifier.uppercased(), isCurrencyCode(regional) { return regional }
    return "EUR"
  }

  static func isCurrencyCode(_ code: String) -> Bool {
    code.count == 3 && code.allSatisfy { $0.isASCII && $0.isUppercase }
  }

  /// Minor units per major unit: 100 for EUR, 1 for JPY.
  static func minorUnitScale(_ currency: String) -> Int64 {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    var scale: Int64 = 1
    for _ in 0..<formatter.maximumFractionDigits { scale *= 10 }
    return scale
  }

  /// "12,50" or "12.50" → 1250 (EUR). Accepts either decimal mark, rounds to the
  /// currency's minor unit, rejects negatives and anything that is not a number.
  static func amountMinor(from text: String, currency: String) -> Int64? {
    var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
    guard !cleaned.isEmpty else { return nil }
    // One separator: it is the decimal mark. Both: the last one is.
    if let lastComma = cleaned.lastIndex(of: ","), let lastDot = cleaned.lastIndex(of: ".") {
      let decimalIsComma = lastComma > lastDot
      cleaned = cleaned.replacingOccurrences(of: decimalIsComma ? "." : ",", with: "")
    }
    cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
    guard cleaned.allSatisfy({ $0.isNumber || $0 == "." }), cleaned.filter({ $0 == "." }).count <= 1,
      let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    else { return nil }
    guard value >= 0 else { return nil }
    var scaled = value * Decimal(minorUnitScale(currency))
    var rounded = Decimal()
    NSDecimalRound(&rounded, &scaled, 0, .plain)
    return NSDecimalNumber(decimal: rounded).int64Value
  }

  /// 1250 EUR → "€12.50" in the given locale.
  static func formatMoney(_ amountMinor: Int64, currency: String, locale: Locale = .current) -> String {
    let code = isCurrencyCode(currency) ? currency : "EUR"
    let major = Decimal(amountMinor) / Decimal(minorUnitScale(code))
    return major.formatted(.currency(code: code).locale(locale))
  }

  /// Totals per currency, in order of first use. Web and iOS can both add
  /// expenses, so a trip can hold more than one currency; they are never summed together.
  static func totals(_ items: [Loci_Trip_ChecklistItem], fallbackCurrency: String) -> [(currency: String, amountMinor: Int64)] {
    var order: [String] = []
    var sums: [String: Int64] = [:]
    for item in self.items(items, kind: .expense) {
      let code = isCurrencyCode(item.currency) ? item.currency : fallbackCurrency
      if sums[code] == nil { order.append(code) }
      sums[code, default: 0] += item.amountMinor
    }
    return order.map { ($0, sums[$0] ?? 0) }
  }

  /// "€12.50 + £3.00", or a zero in the trip's currency when there is nothing yet.
  static func totalLabel(_ items: [Loci_Trip_ChecklistItem], fallbackCurrency: String, locale: Locale = .current) -> String {
    let totals = totals(items, fallbackCurrency: fallbackCurrency)
    guard !totals.isEmpty else { return formatMoney(0, currency: fallbackCurrency, locale: locale) }
    return totals.map { formatMoney($0.amountMinor, currency: $0.currency, locale: locale) }.joined(separator: " + ")
  }
}
