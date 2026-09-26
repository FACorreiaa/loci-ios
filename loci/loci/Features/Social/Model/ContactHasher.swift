import CryptoKit
import Foundation

/// Turns address-book entries into the hashes MatchContacts takes: SHA-256,
/// lower-case hex, of E.164 phone numbers and trimmed, lower-cased emails.
/// Only hashes leave the phone.
nonisolated enum ContactHasher {
  /// Calling codes for the regions most Loci users are in, and whether their
  /// national numbers carry a trunk "0" that E.164 drops. A number already in
  /// international form ("+…" or "00…") needs neither.
  private static let regions: [String: (code: String, trunkZero: Bool)] = [
    "PT": ("351", false),
    "ES": ("34", false),
    "FR": ("33", true),
    "DE": ("49", true),
    "IT": ("39", false),
    "GB": ("44", true),
    "IE": ("353", true),
    "NL": ("31", true),
    "BE": ("32", true),
    "CH": ("41", true),
    "AT": ("43", true),
    "PL": ("48", false),
    "SE": ("46", true),
    "NO": ("47", false),
    "DK": ("45", false),
    "FI": ("358", true),
    "GR": ("30", false),
    "US": ("1", false),
    "CA": ("1", false),
    "BR": ("55", true),
    "MX": ("52", false),
    "AR": ("54", true),
    "AU": ("61", true),
    "NZ": ("64", true),
    "JP": ("81", true),
    "IN": ("91", true),
    "ZA": ("27", true),
    "AO": ("244", false),
    "MZ": ("258", false),
    "CV": ("238", false),
  ]

  /// E.164 for a phone number as typed in Contacts, or nil when it cannot be
  /// placed (too short, or national with an unknown region).
  static func e164(_ raw: String, region: String?) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    var digits = trimmed.filter(\.isNumber)
    let international: Bool
    if trimmed.hasPrefix("+") {
      international = true
    } else if digits.hasPrefix("00") {
      digits.removeFirst(2)
      international = true
    } else {
      international = false
    }
    if !international {
      guard let region = region?.uppercased(), let info = regions[region] else { return nil }
      if info.trunkZero, digits.hasPrefix("0") { digits.removeFirst() }
      digits = info.code + digits
    }
    guard (8...15).contains(digits.count) else { return nil }
    return "+" + digits
  }

  static func normalizedEmail(_ raw: String) -> String? {
    let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return email.contains("@") ? email : nil
  }

  static func sha256Hex(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  /// Every distinct hash for one contact's phones and emails; the caller keeps
  /// which contact each came from, so a match can name who it was.
  static func hashes(phones: [String], emails: [String], region: String?) -> [String] {
    let identifiers = phones.compactMap { e164($0, region: region) } + emails.compactMap(normalizedEmail)
    return Array(Set(identifiers.map(sha256Hex))).sorted()
  }
}
