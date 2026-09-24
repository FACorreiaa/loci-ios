import CoreLocation
import Foundation
import LociConnectProto

/// Contribute's page: the scout's profile, the knowledge-gap tasks (paged),
/// places waiting on a second scout, and the missing-place search.
@MainActor @Observable final class ContributeStore {
  enum Phase: Equatable {
    case idle, loading, loaded
    case failed(String)
  }

  private(set) var phase = Phase.idle
  private(set) var tasks: [VerificationTask] = []
  private(set) var profile = ContributorProfile.empty
  private(set) var pending: [PendingPlace] = []
  /// Confirmed places leave the pending feed on the next load, so they are
  /// kept here long enough for the scout to read what their confirmation did.
  private(set) var confirmed: [String: (place: PendingPlace, outcome: PlaceSubmissionResult)] = [:]
  private(set) var confirming: Set<String> = []
  private(set) var confirmFailed: Set<String> = []
  private(set) var page = 1

  // Missing-place search.
  var query = ""
  var city = ""
  private(set) var searchContext: ContributeSearchContext?
  private(set) var results: [Loci_Poi_POIDetailedInfo] = []
  private(set) var isSearching = false
  private(set) var hasSearched = false
  private(set) var searchError: String?

  var error: String?

  let service: ContributeService

  init(service: ContributeService = ConnectContributeService()) {
    self.service = service
  }

  var pageCount: Int { TaskPaging.pageCount(tasks.count) }
  var visibleTasks: [VerificationTask] { TaskPaging.slice(tasks, page: page) }
  var pageRange: (start: Int, end: Int) { TaskPaging.range(page: page, total: tasks.count) }

  /// Live pending places, then the ones confirmed here that the server has since dropped.
  var shownPending: [PendingPlace] {
    let liveIDs = Set(pending.map(\.submissionID))
    let settled = confirmed.values.map(\.place).filter { !liveIDs.contains($0.submissionID) }.sorted { $0.name < $1.name }
    return pending + settled
  }

  func outcome(for place: PendingPlace) -> PlaceSubmissionResult? { confirmed[place.submissionID]?.outcome }

  /// Tasks decide the page's state; the profile and the pending feed are
  /// extras, so their failures leave them empty rather than failing the page.
  func load() async {
    if tasks.isEmpty { phase = .loading }
    async let tasksCall = service.tasks()
    async let profileCall = try? service.profile()
    async let pendingCall = try? service.pendingPlaces()
    do {
      tasks = try await tasksCall
      page = TaskPaging.clamp(page, total: tasks.count)
      phase = .loaded
    } catch {
      phase = .failed(error.userMessage)
    }
    if let loadedProfile = await profileCall { profile = loadedProfile }
    if let loadedPending = await pendingCall { pending = loadedPending }
  }

  func goToPage(_ next: Int) {
    page = TaskPaging.clamp(next, total: tasks.count)
  }

  /// web: pickMissing → resolveTask. A searched place already on the gap list keeps its fields.
  func task(for poi: Loci_Poi_POIDetailedInfo) -> VerificationTask {
    VerificationTask.resolve(id: poi.id, name: poi.name, in: tasks)
  }

  func confirm(_ place: PendingPlace) async {
    guard !confirming.contains(place.submissionID) else { return }
    confirming.insert(place.submissionID)
    confirmFailed.remove(place.submissionID)
    defer { confirming.remove(place.submissionID) }
    do {
      let outcome = try await service.confirmPlace(submissionID: place.submissionID)
      confirmed[place.submissionID] = (place, outcome)
      if let refreshed = try? await service.pendingPlaces() { pending = refreshed }
      if let refreshed = try? await service.profile() { profile = refreshed }
    } catch {
      confirmFailed.insert(place.submissionID)
    }
  }

  /// Location is read once, only if already allowed; the city it names fills an empty City field.
  func prepareSearch() async {
    guard searchContext == nil, let context = await service.searchContext() else { return }
    searchContext = context
    if city.trimmingCharacters(in: .whitespaces).isEmpty { city = context.city }
  }

  var canSearch: Bool {
    ContributePayload.search(query: query, city: city, coordinate: searchContext?.coordinate) != nil && !isSearching
  }

  func search() async {
    guard canSearch else { return }
    isSearching = true
    hasSearched = true
    searchError = nil
    defer { isSearching = false }
    do {
      results = try await service.searchPlaces(query: query, city: city, coordinate: searchContext?.coordinate)
    } catch {
      results = []
      searchError = "We couldn't search places. Try again."
    }
  }

  /// A report or a new place changed the counts.
  func refreshProfile() async {
    if let refreshed = try? await service.profile() { profile = refreshed }
  }
}

/// One field report about one place (web: ClaimForm + FieldPicker).
@MainActor @Observable final class ClaimFormStore {
  let task: VerificationTask
  private(set) var field: Loci_Place_PlaceFactField?
  private(set) var tokens: [String] = []
  var hours = OpeningHours.default
  private(set) var isSubmitting = false
  private(set) var result: ClaimResult?
  var error: String?

  let service: ContributeService
  /// Called after a report is filed, so the page behind can refresh its counts.
  var onSubmitted: (() -> Void)?

  init(task: VerificationTask, service: ContributeService = ConnectContributeService(), field: Loci_Place_PlaceFactField? = nil) {
    self.task = task
    self.service = service
    // A task can arrive with nothing left to ask, so the first field is not assumed.
    self.field = field.flatMap { task.requestedFields.contains($0) ? $0 : nil } ?? task.requestedFields.first
  }

  var vocabulary: FieldVocabulary? { field.flatMap(PlaceFactVocabulary.vocabulary(for:)) }
  var isStructured: Bool { vocabulary?.kind == .structured }

  func select(_ next: Loci_Place_PlaceFactField) {
    guard next != field else { return }
    field = next
    tokens = []
    result = nil
  }

  func toggle(_ token: String) {
    guard let field else { return }
    tokens = PlaceFactVocabulary.toggle(token, in: tokens, field: field)
    result = nil
  }

  /// What goes on the wire: the encoded week, or one value per answer.
  var claimValues: [String] {
    guard let field else { return [] }
    return isStructured ? [hours.encoded] : PlaceFactVocabulary.claimValues(field, tokens: tokens)
  }

  var isReady: Bool {
    guard field != nil else { return false }
    return isStructured ? hours.isValid : !tokens.isEmpty
  }

  func submit() async {
    guard let field, isReady, !isSubmitting else { return }
    let values = claimValues
    isSubmitting = true
    defer { isSubmitting = false }
    do {
      let outcome = try await service.submitClaims(poiID: task.poiID, field: field, values: values)
      result = outcome
      Analytics.capture(
        .placeClaimSubmitted,
        ["field": PlaceFactVocabulary.wireName(field), "status": outcome.statusName, "poiId": task.poiID, "answers": values.count]
      )
      tokens = []
      onSubmitted?()
    } catch {
      self.error = error.userMessage
    }
  }
}

/// The Add place form (web: AddPlaceForm).
@MainActor @Observable final class AddPlaceStore {
  private(set) var draft: PlaceDraft
  private(set) var isSubmitting = false
  private(set) var result: PlaceSubmissionResult?
  var error: String?

  let service: ContributeService
  var onSubmitted: (() -> Void)?

  init(service: ContributeService = ConnectContributeService(), city: String = "") {
    self.service = service
    draft = PlaceDraft(cityName: city)
  }

  var name: String {
    get { draft.name }
    set { draft.setName(newValue) }
  }

  var cityName: String {
    get { draft.cityName }
    set { draft.setCityName(newValue) }
  }

  var category: String {
    get { draft.category }
    set { draft.setCategory(newValue) }
  }

  func submit() async {
    guard draft.isReady, !isSubmitting else { return }
    isSubmitting = true
    result = nil
    defer { isSubmitting = false }
    do {
      let submitted = try await service.submitPlace(draft)
      result = submitted
      Analytics.capture(.placeSubmitted, ["city": draft.cityName.trimmingCharacters(in: .whitespacesAndNewlines)])
      draft.clearAfterSubmit()
      onSubmitted?()
    } catch {
      self.error = error.userMessage
    }
  }
}
