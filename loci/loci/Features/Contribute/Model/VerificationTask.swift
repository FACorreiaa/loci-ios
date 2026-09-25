import Foundation
import LociConnectProto
import SwiftProtobuf

/// A place the server wants a fresh look at, and the fields it is asking about.
nonisolated struct VerificationTask: Identifiable, Hashable, Sendable {
  let poiID: String
  let poiName: String
  let requestedFields: [Loci_Place_PlaceFactField]
  var oldestFactAt: Date?

  var id: String { poiID }

  init(poiID: String, poiName: String, requestedFields: [Loci_Place_PlaceFactField], oldestFactAt: Date? = nil) {
    self.poiID = poiID
    self.poiName = poiName
    self.requestedFields = requestedFields
    self.oldestFactAt = oldestFactAt
  }

  /// Fields this build has no question for are dropped, as web drops the ones
  /// its bundle doesn't know: the server may be ahead of the app.
  init(_ proto: Loci_Place_VerificationTask) {
    self.init(
      poiID: proto.poiID,
      poiName: proto.poiName,
      requestedFields: proto.requestedFields.filter { PlaceFactVocabulary.vocabulary(for: $0) != nil },
      oldestFactAt: proto.hasOldestFactAt ? proto.oldestFactAt.date : nil
    )
  }

  /// web: taskFromPlace. A catalogued place off the gap list still has
  /// something to file: every field we know how to ask.
  static func fromPlace(id: String, name: String) -> VerificationTask {
    VerificationTask(poiID: id, poiName: name, requestedFields: PlaceFactVocabulary.contributableFields)
  }

  /// web: resolveTask. Prefer the server's gap list when the place is already on it.
  static func resolve(id: String, name: String, in tasks: [VerificationTask]) -> VerificationTask {
    tasks.first { $0.poiID == id } ?? fromPlace(id: id, name: name)
  }
}

/// Contribute's task list in short pages, so the other actions stay in reach
/// (web: `lib/contribute/paginate.ts`). Pages are 1-based.
nonisolated enum TaskPaging {
  static let tasksPerPage = 5

  static func pageCount(_ total: Int, pageSize: Int = tasksPerPage) -> Int {
    guard total > 0 else { return 1 }
    return (total + pageSize - 1) / pageSize
  }

  static func clamp(_ page: Int, total: Int, pageSize: Int = tasksPerPage) -> Int {
    guard page >= 1 else { return 1 }
    return min(page, pageCount(total, pageSize: pageSize))
  }

  static func slice<T>(_ items: [T], page: Int, pageSize: Int = tasksPerPage) -> [T] {
    let current = clamp(page, total: items.count, pageSize: pageSize)
    let start = (current - 1) * pageSize
    guard start < items.count else { return [] }
    return Array(items[start..<min(start + pageSize, items.count)])
  }

  /// 1-based, inclusive: "Places 11–12 of 12". (0, 0) for an empty list.
  static func range(page: Int, total: Int, pageSize: Int = tasksPerPage) -> (start: Int, end: Int) {
    guard total > 0 else { return (0, 0) }
    let current = clamp(page, total: total, pageSize: pageSize)
    return ((current - 1) * pageSize + 1, min(current * pageSize, total))
  }

  /// 0-based index → 1-based page.
  static func pageOf(_ index: Int, pageSize: Int = tasksPerPage) -> Int {
    guard index >= 0 else { return 1 }
    return index / pageSize + 1
  }
}

/// What the scout is told about the report they just filed.
nonisolated enum ClaimOutcome: Equatable, Sendable {
  /// Another scout saw the same thing: it is on the field guide now.
  case verified
  /// Another scout saw something different.
  case contradicted
  /// Waiting on a second scout (`pending`), or a status this build doesn't know.
  case recorded(pending: Bool)

  init(_ status: Loci_Place_PlaceClaimStatus) {
    switch status {
    case .accepted: self = .verified
    case .contradicted: self = .contradicted
    default: self = .recorded(pending: status == .pending)
    }
  }
}

nonisolated struct ClaimResult: Equatable, Sendable {
  let claimID: String
  let status: Loci_Place_PlaceClaimStatus

  static let empty = ClaimResult(claimID: "", status: .unspecified)

  /// web: useSubmitPlaceClaims. Several answers are several claims; the
  /// scout is told the best any of them reached: ACCEPTED, then PENDING, then the first.
  static func best(_ results: [ClaimResult]) -> ClaimResult {
    results.first { $0.status == .accepted } ?? results.first { $0.status == .pending } ?? results.first ?? .empty
  }

  /// web's ClaimStatus name, as `place_claim_submitted` carries it.
  var statusName: String {
    switch status {
    case .pending: "PENDING"
    case .accepted: "ACCEPTED"
    case .contradicted: "CONTRADICTED"
    case .expired: "EXPIRED"
    default: "UNSPECIFIED"
    }
  }
}

nonisolated struct ContributorProfile: Equatable, Sendable {
  var reputation = 0
  var submittedClaims = 0
  var acceptedClaims = 0
  var badges: [String] = []

  static let empty = ContributorProfile()

  init(reputation: Int = 0, submittedClaims: Int = 0, acceptedClaims: Int = 0, badges: [String] = []) {
    self.reputation = reputation
    self.submittedClaims = submittedClaims
    self.acceptedClaims = acceptedClaims
    self.badges = badges
  }

  init(_ proto: Loci_Place_ContributorProfile) {
    self.init(
      reputation: Int(proto.reputation),
      submittedClaims: Int(proto.submittedClaims),
      acceptedClaims: Int(proto.acceptedClaims),
      badges: proto.badges
    )
  }
}

/// A badge slug in words. The server awards `local-scout` at ten verified
/// reports (placeintel `creditCorroborators`); anything newer reads as its slug.
nonisolated enum ScoutBadge {
  static func title(_ slug: String) -> String {
    switch slug {
    case "local-scout": return "Local scout"
    default:
      let words = slug.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
      return words.prefix(1).uppercased() + words.dropFirst()
    }
  }

  static func detail(_ slug: String) -> String? { slug == "local-scout" ? "Ten reports verified by another scout" : nil }
}

/// A place somebody else proposed, waiting on a second pair of eyes.
nonisolated struct PendingPlace: Identifiable, Hashable, Sendable {
  let submissionID: String
  let name: String
  let cityName: String
  var category: String?
  var address: String?
  var confirmationsNeeded = 0

  var id: String { submissionID }

  init(submissionID: String, name: String, cityName: String, category: String? = nil, address: String? = nil, confirmationsNeeded: Int = 0) {
    self.submissionID = submissionID
    self.name = name
    self.cityName = cityName
    self.category = category
    self.address = address
    self.confirmationsNeeded = confirmationsNeeded
  }

  init(_ proto: Loci_Place_PendingPlace) {
    self.init(
      submissionID: proto.submissionID,
      name: proto.name,
      cityName: proto.cityName,
      category: proto.hasCategory && !proto.category.isEmpty ? proto.category : nil,
      address: proto.hasAddress && !proto.address.isEmpty ? proto.address : nil,
      confirmationsNeeded: Int(proto.confirmationsNeeded)
    )
  }

  /// "Lisbon · cafe".
  var subtitle: String { [cityName, category ?? ""].filter { !$0.isEmpty }.joined(separator: " · ") }
}

/// What a submit or a confirm did: `promoted` means this was the second voice
/// and the place is on the guide now.
nonisolated struct PlaceSubmissionResult: Equatable, Sendable {
  let submissionID: String
  let promoted: Bool
  let confirmationsNeeded: Int

  var message: String {
    promoted
      ? "Another scout had already proposed this place. With you, it is on the guide now."
      : "Recorded. One more scout needs to confirm this place exists."
  }
}

/// The Add place form. `submissionID` stays the same while the draft does, so
/// a retry after a dropped response is recognised as a repeat; changing any
/// field makes it a different place and a new id (web: AddPlaceForm's draftId).
nonisolated struct PlaceDraft: Equatable, Sendable {
  static let nameLimit = 300
  static let cityLimit = 200
  static let categoryLimit = 100

  private(set) var name = ""
  private(set) var cityName = ""
  private(set) var category = ""
  private(set) var submissionID: String

  init(name: String = "", cityName: String = "", category: String = "", makeID: () -> String = { UUID().uuidString.lowercased() }) {
    self.name = String(name.prefix(Self.nameLimit))
    self.cityName = String(cityName.prefix(Self.cityLimit))
    self.category = String(category.prefix(Self.categoryLimit))
    submissionID = makeID()
  }

  mutating func setName(_ value: String, makeID: () -> String = { UUID().uuidString.lowercased() }) {
    update(\.name, String(value.prefix(Self.nameLimit)), makeID)
  }

  mutating func setCityName(_ value: String, makeID: () -> String = { UUID().uuidString.lowercased() }) {
    update(\.cityName, String(value.prefix(Self.cityLimit)), makeID)
  }

  mutating func setCategory(_ value: String, makeID: () -> String = { UUID().uuidString.lowercased() }) {
    update(\.category, String(value.prefix(Self.categoryLimit)), makeID)
  }

  /// web: a name of two or more characters and a city.
  var isReady: Bool {
    name.trimmingCharacters(in: .whitespacesAndNewlines).count > 1 && !cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// After a successful submit web clears the name and kind and keeps the
  /// city, so the next place starts a new draft in the same city.
  mutating func clearAfterSubmit(makeID: () -> String = { UUID().uuidString.lowercased() }) {
    name = ""
    category = ""
    submissionID = makeID()
  }

  private mutating func update(_ path: WritableKeyPath<PlaceDraft, String>, _ value: String, _ makeID: () -> String) {
    guard self[keyPath: path] != value else { return }
    self[keyPath: path] = value
    submissionID = makeID()
  }
}
