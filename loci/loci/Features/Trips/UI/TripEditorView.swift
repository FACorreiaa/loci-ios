import Connect
import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// The trip page (web: /trips/:id). Every edit is one TripService RPC that
/// returns the new TripDraft, whose `version` is the next `baseVersion`, so a
/// stale edit from another device is refused by the server rather than merged;
/// the refusal raises "This trip changed on another device" and a reload.
///
/// The page is split into its web components: `TripHero`,
/// `TripPreferencesSection`, the days, `TripExportSection` and
/// `TripChecklistsSection`. The trip is read cache-through (`LocalCache`,
/// kind `.trip`): the phone's copy draws at once, GetTrip replaces it, and a
/// copy the server could not confirm is shown read-only with the cache chip.
struct TripEditorView: View {
  let tripID: String

  @State private var trip: Loci_Trip_TripDraft?

  @State private var driveCost: DriveCostModel?
  @State private var loaded: Loaded<Loci_Trip_TripDraft>?
  @State private var isEditing = false
  @State private var renaming: Loci_Trip_TripStop?
  @State private var isRenaming = false
  @State private var renameText = ""
  @State private var picking: PickerTarget?
  @State private var error: String?
  @State private var hasConflict = false
  @State private var side = ResultsSideData()
  @State private var checklist: TripChecklistStore
  @State private var editQueue: Task<Void, Never>?
  /// The day being walked stop by stop (pushed as WalkDayView).
  @State private var walkingDay: WalkDay?
  @State private var planning = false
  /// A shared trip's open suggestions; empty on a trip planned alone.
  @State private var proposals: [Loci_Chat_ActionProposal] = []
  /// A shared trip's comments, and the stop the composer is about ("" for the trip).
  @State private var comments: [Loci_Trip_TripComment] = []
  @State private var commentAbout = ""
  /// A trip brief's `?swap=<stop>`: the stop to open the swap picker on, once.
  @State private var swapStopID: String?
  @Environment(\.dismiss) private var dismiss
  private let tripActions: TripActionService = ConnectTripActionService()

  /// Design previews pass a trip and a checklist and never touch the network.
  private let isOffline: Bool
  private let expandsPreferences: Bool

  init(
    tripID: String,
    trip: Loci_Trip_TripDraft? = nil,
    checklist: TripChecklistStore? = nil,
    isOffline: Bool = false,
    expandsPreferences: Bool = false,
    swapStopID: String? = nil
  ) {
    _swapStopID = State(initialValue: swapStopID)
    self.tripID = tripID
    self.isOffline = isOffline
    self.expandsPreferences = expandsPreferences
    _trip = State(initialValue: trip)
    _checklist = State(initialValue: checklist ?? TripChecklistStore(tripID: tripID))
  }

  enum PickerTarget: Identifiable {
    case add(dayID: String)
    case replace(stopID: String)

    var id: String {
      switch self {
      case .add(let dayID): "add-\(dayID)"
      case .replace(let stopID): "replace-\(stopID)"
      }
    }
  }

  var body: some View {
    Group {
      if let trip {
        List {
          Section {
            TripHero(trip: trip)
              .listRowInsets(EdgeInsets())
              .listRowBackground(Color.clear)
          }
          togetherSections(trip)
          if isOwner {
            Section {
              NavigationLink(value: AppRoute.tripJournal(id: tripID)) {
                Label {
                  VStack(alignment: .leading, spacing: 2) {
                    Text("Journal").font(.lociHeadline())
                    Text("Your notes and photos, day by day.")
                      .font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
                  }
                } icon: {
                  Image(systemName: "book").foregroundStyle(Color.lociCoral)
                }
              }
            }
          }
          if RecapRules.tripHasEnded(trip) {
            Section {
              NavigationLink(value: AppRoute.tripRecap(id: tripID)) {
                Label {
                  VStack(alignment: .leading, spacing: 2) {
                    Text("Your trip recap").font(.lociHeadline())
                    Text("The places, the kilometres and what Loci learned about your taste.")
                      .font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
                  }
                } icon: {
                  Image(systemName: "sparkles").foregroundStyle(Color.lociCoral)
                }
              }
            }
          }
          if let loaded, loaded.staleSince != nil {
            Section {
              CacheChip(loaded: loaded)
              if !canEdit { Text("Connect to edit").lociCoordStyle(10) }
            }
            .listRowBackground(Color.clear)
          }
          TripPreferencesSection(constraints: trip.constraints, startsExpanded: expandsPreferences) { setPreference($0) }
            .disabled(!canEdit)
          TripPlanSection(
            trip: trip,
            onSetDates: { start, end in enqueue { await setDates(start, end) } },
            onSetStay: { stay in enqueue { await setStay(stay) } },
            onAddFlight: { flight in enqueue { await addFlight(flight) } },
            onRemoveFlight: { id in enqueue { await removeFlight(id) } }
          )
            .disabled(!canEdit)
          ForEach(trip.days, id: \.id) { day in daySection(day, trip: trip) }
          if !trip.legs.isEmpty { legsSection(trip.legs) }
          TripExportSection(trip: trip, isPro: side.isPro)
          // Packing and expenses are the owner's own lists.
          if isOwner { TripChecklistsSection(store: checklist) }
        }
      } else {
        ProgressView()
      }
    }
    .settingsStyle(trip?.title ?? "Trip")
    .environment(\.editMode, .constant(isEditing ? .active : .inactive))
    .onChange(of: canChange) { _, ok in if !ok { isEditing = false } }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(isEditing ? "Done" : (isOwner ? "Edit" : "Suggest")) { isEditing.toggle() }.disabled(!canChange)
      }
      if let trip, !isOffline, isOwner {
        ToolbarItem(placement: .secondaryAction) { TripShareMenu(trip: trip).id(trip.id) }
      }
      // A co-planner's asks become suggestions for the owner.
      if canChange, !isOffline {
        ToolbarItem(placement: .primaryAction) {
          Button { planning = true } label: { Label("Ask the planner", systemImage: "bubble.left.and.text.bubble.right") }
        }
      }
    }
    .sheet(isPresented: $planning) {
      if let trip {
        TripPlannerSheet(
          trip: trip,
          currentVersion: { self.trip?.version },
          onTripChanged: { next in Task { await adopt(next) } },
          onReloadTrip: { await reload() }
        )
      }
    }
    .alert("Rename stop", isPresented: $isRenaming, presenting: renaming) { stop in
      TextField("Name", text: $renameText)
      Button("Cancel", role: .cancel) {}
      Button("Save") { enqueue { await rename(stop, to: renameText) } }
    }
    .alert("This trip changed on another device", isPresented: $hasConflict) {
      Button("Reload") { Task { await reload() } }
    } message: {
      Text("Your last change wasn't saved. Reload to see the latest version, then try again.")
    }
    .navigationDestination(item: $walkingDay) { WalkDayView(day: $0) }
    .sheet(item: $picking) { target in
      PlacePicker(cityName: trip?.cityName ?? "") { poi in
        enqueue {
          switch target {
          case .add(let dayID): await add(poi, toDay: dayID)
          case .replace(let stopID): await replace(stopID, with: poi)
          }
        }
      }
    }
    .errorAlert($error)
    .errorAlert($checklist.error)
    .task { await load() }
  }

  // MARK: - Sections

  /// Planning together: who is on the trip, their suggestions and their comments.
  @ViewBuilder
  private func togetherSections(_ trip: Loci_Trip_TripDraft) -> some View {
    if !isOffline {
      TripMembersSection(trip: trip, isOwner: isOwner) { dismiss() }
    }
    if !proposals.isEmpty {
      TripProposalsSection(
        proposals: proposals,
        isOwner: isOwner,
        currentUserID: AuthSessionManager.shared.currentUserID,
        canApply: canEdit,
        onApply: { await applyProposal($0) },
        onDismiss: { await dismissProposal($0) },
        onReact: { await react($0, $1) }
      )
    }
    if !isOffline, isShared(trip) {
      TripCommentsSection(
        comments: comments,
        stops: trip.days.flatMap(\.stops),
        aboutStopID: $commentAbout,
        onPost: { await postComment($0, stopID: $1) },
        onDelete: { await deleteComment($0) },
        onReport: { await reportComment($0, reason: $1) },
        onBlock: { await blockAuthor($0) }
      )
    }
  }

  private func daySection(_ day: Loci_Trip_TripDay, trip: Loci_Trip_TripDraft) -> some View {
    Section {
      ForEach(day.stops, id: \.id) { stop in
        // Retiming stays the owner's; a co-planner's edits become suggestions.
        StopRow(stop: stop, color: LociTheme.dayColor(Int(day.dayNumber)), isEditing: isEditing && canEdit) { minutes in
          enqueue { await setDuration(stop, minutes: minutes) }
        }
        .moveDisabled(!canChange)
        .swipeActions(edge: .trailing) {
          if canChange {
            Button(isOwner ? "Remove" : "Suggest removing", role: .destructive) { enqueue { await remove(stop) } }
            Button(isOwner ? "Replace" : "Suggest a swap") { picking = .replace(stopID: stop.id) }.tint(.lociCoralFill)
          }
        }
        .swipeActions(edge: .leading) {
          if canEdit {
            Button("Rename") {
              renameText = stop.name
              renaming = stop
              isRenaming = true
            }.tint(.lociForest)
          }
        }
      }
      .onMove { from, to in
        guard isOwner else {
          // The row snaps back: the move waits for the owner to apply it.
          guard let index = from.first else { return }
          let change = SuggestedChange.move(
            stopID: day.stops[index].id,
            toDayID: day.id,
            toIndex: SuggestedChange.moveIndex(from: index, toOffset: to)
          )
          Task { await suggest(change) }
          return
        }
        var ids = day.stops.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        enqueue { await reorder(day, ids: ids) }
      }
      if isEditing {
        Button(isOwner ? "Add a place to day \(day.dayNumber)" : "Suggest a place for day \(day.dayNumber)", systemImage: "plus") {
          picking = .add(dayID: day.id)
        }
      }
    } header: {
      HStack {
        Circle().fill(LociTheme.dayColor(Int(day.dayNumber))).frame(width: 10, height: 10)
        if day.cityName.isEmpty || day.cityName == trip.cityName {
          Text("Day \(day.dayNumber)")
        } else {
          Text("Day \(day.dayNumber) · \(day.cityName)")
        }
        let walkDay = WalkDay.from(trip: trip, day: day)
        Button("Walk", systemImage: "figure.walk") { walkingDay = walkDay }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .disabled(walkDay.stops.isEmpty)
          .accessibilityLabel("Walk day \(day.dayNumber)")
        if DayTimeline.today(in: trip)?.id == day.id {
          Spacer()
          TodayControls(trip: trip, day: day).textCase(nil)
        }
        if let date = DayTimeline.localMidnight(of: day) { Spacer(); Text(date, style: .date) }
      }
    }
  }

  private func legsSection(_ legs: [Loci_Trip_TripLeg]) -> some View {
    Section("Travel between cities") {
      ForEach(legs, id: \.id) { leg in
        VStack(alignment: .leading, spacing: 2) {
          Text("\(leg.fromName) → \(leg.toName)")
          Text("\(leg.mode) · \(Int(leg.distanceKm)) km · \(leg.durationMins / 60)h \(leg.durationMins % 60)m · after day \(leg.afterDay)").lociCoordStyle(10)
        }
      }
      if let driveCost { DriveCostRow(model: driveCost) }
    }
    .task(id: DriveCostModel.totalKm(legs)) { await loadDriveCost(km: DriveCostModel.totalKm(legs)) }
  }

  /// web: TripMoney — every leg's km summed; zero or a failure hides the line.
  private func loadDriveCost(km: Double) async {
    guard km > 0, !ResultsSideData.isOffline else { driveCost = nil; return }
    guard let estimate = try? await LocalContextAPI.driveCost(km: km) else { return }
    driveCost = DriveCostModel(estimate)
  }

  // MARK: - Loading

  /// The phone's copy first, then the server, the plan and the checklists
  /// together. Offline keeps the copy, read-only.
  private func load() async {
    guard !isOffline else { return }
    async let plan: Void = side.loadPlan()
    await reload()
    openSwapFromBrief()
    async let notes: Void = loadComments()
    await loadProposals()
    _ = await notes
    // A member's GetTripChecklist is NotFound; only the owner has lists.
    if isOwner { await checklist.load() }
    _ = await plan
  }

  /// GetTrip through the cache; also what the conflict alert's Reload runs.
  private func reload() async {
    var request = Loci_Trip_GetTripRequest()
    request.tripID = tripID
    let sent = request
    loaded = await cacheThrough(Loci_Trip_TripDraft.self, kind: .trip, id: tripID, onCached: { trip = $0.value }) {
      try await rpc("Could not load the trip.", sent) { await TripAPI.client.getTrip(request: $0, headers: [:]) }
    }
    if let value = loaded?.value { trip = value } else if case .missing(let reason) = loaded { error = reason.userMessage }
  }

  /// Edits need the server; a copy the server has not confirmed is read-only.
  /// Only the owner edits; a co-planner suggests, a viewer reads.
  private var canEdit: Bool { isOwner && isConfirmed }

  /// A co-planner's adds, swaps, moves and removals go to the owner as suggestions.
  private var canSuggest: Bool { trip?.viewerRole == .coPlanner && isConfirmed }

  private var canChange: Bool { canEdit || canSuggest }

  private var isConfirmed: Bool {
    switch loaded {
    case .fresh, nil: true
    case .stale, .missing: false
    }
  }

  /// The server sets `owner` only when someone else reads the trip: here, a member.
  private var isOwner: Bool { !(trip?.hasOwner ?? false) }

  /// Take the server's trip as the new truth; the copy follows it.
  private func adopt(_ next: Loci_Trip_TripDraft) async {
    trip = next
    loaded = .fresh(next)
    guard !isOffline else { return }
    try? await LocalCache.shared.put(next, kind: .trip, id: tripID)
  }

  // MARK: - Edits

  /// Run an edit and adopt the trip the server returns; a stale `baseVersion`
  /// raises the conflict alert instead of a generic error.
  private func apply<Input: Sendable>(
    _ fallback: String,
    _ request: Input,
    _ call: @escaping @Sendable (Input) async -> ResponseMessage<Loci_Trip_TripDraft>
  ) async {
    do {
      let next = try await TripAPI.call(fallback, request, call)
      await adopt(next)
    } catch {
      if error.isVersionConflict {
        hasConflict = true
      } else if !error.isCancelled {
        self.error = error.message
      }
    }
  }

  // MARK: - Plan (dates, stays, flights)

  private func setDates(_ start: String, _ end: String) async {
    guard let trip else { return }
    var request = Loci_Trip_SetTripDatesRequest()
    request.tripID = trip.id
    request.startDate = start
    request.endDate = end
    request.baseVersion = trip.version
    await apply("Could not save the dates.", request) { await TripAPI.client.setTripDates(request: $0, headers: [:]) }
  }

  private func setStay(_ stay: Loci_Trip_TripStay) async {
    guard let trip else { return }
    var request = Loci_Trip_SetStayRequest()
    request.tripID = trip.id
    request.stay = stay
    request.baseVersion = trip.version
    await apply("Could not save the hotel.", request) { await TripAPI.client.setStay(request: $0, headers: [:]) }
  }

  private func addFlight(_ flight: Loci_Trip_TripFlight) async {
    guard let trip else { return }
    var request = Loci_Trip_AddFlightRequest()
    request.tripID = trip.id
    request.flight = flight
    request.baseVersion = trip.version
    await apply("Could not save the flight.", request) { await TripAPI.client.addFlight(request: $0, headers: [:]) }
  }

  private func removeFlight(_ id: String) async {
    guard let trip else { return }
    var request = Loci_Trip_RemoveFlightRequest()
    request.tripID = trip.id
    request.flightID = id
    request.baseVersion = trip.version
    await apply("Could not remove the flight.", request) { await TripAPI.client.removeFlight(request: $0, headers: [:]) }
  }

  /// Preference edits run one after another: each needs the `version` the
  /// previous one returned, or the second would be refused as a conflict.
  private func setPreference(_ patch: PreferencePatch) {
    enqueue { await sendPreference(patch) }
  }

  /// Every edit that sends `baseVersion` runs one after another on the same
  /// queue: two quick edits would otherwise both send the version before
  /// either landed, and the second would be refused as a change from another
  /// device.
  private func enqueue(_ edit: @escaping @MainActor () async -> Void) {
    let previous = editQueue
    editQueue = Task {
      await previous?.value
      await edit()
    }
  }

  private func sendPreference(_ patch: PreferencePatch) async {
    guard let trip else { return }
    var request = Loci_Trip_SetConstraintRequest()
    request.tripID = trip.id
    request.constraints = TripFormat.merged(trip.constraints, with: patch)
    request.baseVersion = trip.version
    guard request.constraints != trip.constraints else { return }
    await apply("Could not save the trip preferences.", request) { await TripAPI.client.setConstraint(request: $0, headers: [:]) }
  }

  private func reorder(_ day: Loci_Trip_TripDay, ids: [String]) async {
    guard let trip else { return }
    var request = Loci_Trip_ReorderStopsRequest()
    request.tripID = trip.id
    request.dayID = day.id
    request.orderedStopIds = ids
    request.baseVersion = trip.version
    await apply("Could not reorder.", request) { await TripAPI.client.reorderStops(request: $0, headers: [:]) }
  }

  private func rename(_ stop: Loci_Trip_TripStop, to name: String) async {
    guard let trip, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    var request = Loci_Trip_RenameStopRequest()
    request.tripID = trip.id
    request.stopID = stop.id
    request.name = name
    request.baseVersion = trip.version
    await apply("Could not rename the stop.", request) { await TripAPI.client.renameStop(request: $0, headers: [:]) }
  }

  private func setDuration(_ stop: Loci_Trip_TripStop, minutes: Int) async {
    guard let trip else { return }
    var request = Loci_Trip_EditStopDurationRequest()
    request.tripID = trip.id
    request.stopID = stop.id
    request.durationMinutes = Int32(minutes)
    if stop.hasStartMinute { request.startMinute = stop.startMinute }
    request.baseVersion = trip.version
    await apply("Could not change the duration.", request) { await TripAPI.client.editStopDuration(request: $0, headers: [:]) }
  }

  /// web: routes/trips/[id].tsx addStop
  private func add(_ poi: Loci_Poi_POIDetailedInfo, toDay dayID: String) async {
    guard let trip, let day = trip.days.first(where: { $0.id == dayID }) else { return }
    guard isOwner else {
      await suggest(.add(dayID: dayID, stop: Self.stop(from: poi, orderIndex: day.stops.count)))
      return
    }
    var request = Loci_Trip_AddStopRequest()
    request.tripID = trip.id
    request.dayID = dayID
    request.stop = Self.stop(from: poi, orderIndex: day.stops.count)
    request.baseVersion = trip.version
    await apply("Could not add the place.", request) { await TripAPI.client.addStop(request: $0, headers: [:]) }
  }

  private func replace(_ stopID: String, with poi: Loci_Poi_POIDetailedInfo) async {
    guard let trip, let old = trip.days.flatMap(\.stops).first(where: { $0.id == stopID }) else { return }
    guard isOwner else {
      await suggest(.replace(stopID: stopID, with: Self.stop(from: poi, orderIndex: Int(old.orderIndex))))
      return
    }
    var request = Loci_Trip_ReplaceStopRequest()
    request.tripID = trip.id
    request.stopID = stopID
    request.replacement = Self.stop(from: poi, orderIndex: Int(old.orderIndex))
    request.baseVersion = trip.version
    await apply("Could not replace the place.", request) { await TripAPI.client.replaceStop(request: $0, headers: [:]) }
  }

  static func stop(from poi: Loci_Poi_POIDetailedInfo, orderIndex: Int) -> Loci_Trip_TripStop {
    var stop = Loci_Trip_TripStop()
    stop.id = UUID().uuidString.lowercased()
    stop.poiID = poi.id
    stop.orderIndex = Int32(orderIndex)
    stop.name = poi.name
    let description = poi.descriptionPoi.isEmpty ? poi.description_p : poi.descriptionPoi
    stop.notes = description.isEmpty ? "Added from place search" : description
    return stop
  }

  private func remove(_ stop: Loci_Trip_TripStop) async {
    guard let trip else { return }
    guard isOwner else {
      await suggest(.remove(stopID: stop.id))
      return
    }
    var request = Loci_Trip_RemoveStopRequest()
    request.tripID = trip.id
    request.stopID = stop.id
    request.baseVersion = trip.version
    await apply("Could not remove the stop.", request) { await TripAPI.client.removeStop(request: $0, headers: [:]) }
  }

  // MARK: - Suggestions (planning together)

  /// Only a trip planned together has suggestions; a solo trip skips the call.
  private func loadProposals() async {
    guard !isOffline, let trip, isShared(trip) else { return }
    if let list = try? await TripProposalsAPI.list(tripID: trip.id) { proposals = list }
  }

  private func suggest(_ change: SuggestedChange) async {
    guard let trip else { return }
    do {
      _ = try await TripProposalsAPI.propose(tripID: trip.id, baseVersion: trip.version, action: change.action)
      await loadProposals()
    } catch {
      self.error = error.userMessage
    }
  }

  /// The owner applies against the trip they see; a stale copy reloads.
  private func applyProposal(_ proposal: Loci_Chat_ActionProposal) async -> String? {
    guard let trip else { return nil }
    do {
      let response = try await tripActions.apply(proposalID: proposal.id, option: nil, baseVersion: trip.version)
      if response.hasTrip { await adopt(response.trip) }
      await loadProposals()
      return nil
    } catch {
      if error.kind == .stale { await reload() }
      return error.tripPageMessage
    }
  }

  private func dismissProposal(_ proposal: Loci_Chat_ActionProposal) async -> String? {
    do {
      try await tripActions.dismiss(proposalID: proposal.id)
      proposals.removeAll { $0.id == proposal.id }
      return nil
    } catch {
      return "Couldn't turn this down. Try again."
    }
  }

  private func react(_ proposal: Loci_Chat_ActionProposal, _ value: Int32) async {
    guard let updated = try? await TripProposalsAPI.react(proposalID: proposal.id, value: value) else { return }
    if let index = proposals.firstIndex(where: { $0.id == updated.id }) { proposals[index] = updated }
  }
}

// MARK: - Comments (planning together)

extension TripEditorView {
  /// A trip someone else is on: a member's view, or an owner with members.
  private func isShared(_ trip: Loci_Trip_TripDraft) -> Bool { !isOwner || !trip.members.isEmpty }

  private func loadComments() async {
    guard !isOffline, let trip, isShared(trip) else { return }
    if let list = try? await TripCommentsAPI.list(tripID: trip.id) { comments = list }
  }

  private func postComment(_ body: String, stopID: String?) async -> String? {
    do {
      comments.append(try await TripCommentsAPI.add(tripID: tripID, body: body, stopID: stopID))
      return nil
    } catch {
      return error.userMessage
    }
  }

  private func deleteComment(_ comment: Loci_Trip_TripComment) async -> String? {
    do {
      try await TripCommentsAPI.delete(commentID: comment.id)
      comments.removeAll { $0.id == comment.id }
      return nil
    } catch {
      return error.userMessage
    }
  }

  /// A reported comment leaves the reporter's view at once, as on the server.
  private func reportComment(_ comment: Loci_Trip_TripComment, reason: String) async -> String? {
    do {
      try await TripCommentsAPI.report(commentID: comment.id, reason: reason)
      comments.removeAll { $0.id == comment.id }
      return nil
    } catch {
      return error.userMessage
    }
  }

  /// Blocking hides both sides' comments; the list is read again to match.
  private func blockAuthor(_ comment: Loci_Trip_TripComment) async -> String? {
    do {
      try await SocialAPI.block(userID: comment.author.id)
      comments.removeAll { $0.author.id == comment.author.id }
      await loadComments()
      return nil
    } catch {
      return error.userMessage
    }
  }

  /// A trip brief that saw a closed stop opens here on the swap picker: a
  /// replace for the owner, a suggested swap for a co-planner. A viewer, or a
  /// stop that has since gone, just shows the trip.
  private func openSwapFromBrief() {
    guard let stopID = swapStopID, let trip else { return }
    swapStopID = nil
    guard canChange, trip.days.contains(where: { $0.stops.contains { $0.id == stopID } }) else { return }
    picking = .replace(stopID: stopID)
  }
}
