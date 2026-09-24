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
  @State private var loaded: Loaded<Loci_Trip_TripDraft>?
  @State private var isEditing = false
  @State private var renaming: Loci_Trip_TripStop?
  @State private var renameText = ""
  @State private var picking: PickerTarget?
  @State private var shareURL: URL?
  @State private var error: String?
  @State private var hasConflict = false
  @State private var side = ResultsSideData()
  @State private var checklist: TripChecklistStore
  @State private var preferenceQueue: Task<Void, Never>?

  /// Design previews pass a trip and a checklist and never touch the network.
  private let isOffline: Bool
  private let expandsPreferences: Bool

  init(
    tripID: String,
    trip: Loci_Trip_TripDraft? = nil,
    checklist: TripChecklistStore? = nil,
    isOffline: Bool = false,
    expandsPreferences: Bool = false
  ) {
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
          if let loaded, loaded.staleSince != nil {
            Section {
              CacheChip(loaded: loaded)
              if !canEdit { Text("Connect to edit").lociCoordStyle(10) }
            }
            .listRowBackground(Color.clear)
          }
          TripPreferencesSection(constraints: trip.constraints, startsExpanded: expandsPreferences) { setPreference($0) }
            .disabled(!canEdit)
          ForEach(trip.days, id: \.id) { day in daySection(day, trip: trip) }
          if !trip.legs.isEmpty { legsSection(trip.legs) }
          TripExportSection(trip: trip, isPro: side.isPro)
          TripChecklistsSection(store: checklist)
        }
      } else {
        ProgressView()
      }
    }
    .settingsStyle(trip?.title ?? "Trip")
    .environment(\.editMode, .constant(isEditing ? .active : .inactive))
    .onChange(of: canEdit) { _, ok in if !ok { isEditing = false } }
    .toolbar {
      ToolbarItem(placement: .primaryAction) { Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }.disabled(!canEdit) }
      ToolbarItem(placement: .secondaryAction) {
        if let shareURL {
          ShareLink(item: shareURL) { Label("Share link", systemImage: "square.and.arrow.up") }
        } else {
          Button("Share", systemImage: "square.and.arrow.up") { Task { await share() } }
        }
      }
    }
    .alert("Rename stop", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
      TextField("Name", text: $renameText)
      Button("Cancel", role: .cancel) {}
      Button("Save") { if let stop = renaming { Task { await rename(stop, to: renameText) } } }
    }
    .alert("This trip changed on another device", isPresented: $hasConflict) {
      Button("Reload") { Task { await reload() } }
    } message: {
      Text("Your last change wasn't saved. Reload to see the latest version, then try again.")
    }
    .sheet(item: $picking) { target in
      PlacePicker(cityName: trip?.cityName ?? "") { poi in
        Task {
          switch target {
          case .add(let dayID): await add(poi, toDay: dayID)
          case .replace(let stopID): await replace(stopID, with: poi)
          }
        }
      }
    }
    .errorAlert($error)
    .task { await load() }
  }

  // MARK: - Sections

  private func daySection(_ day: Loci_Trip_TripDay, trip: Loci_Trip_TripDraft) -> some View {
    Section {
      ForEach(day.stops, id: \.id) { stop in
        StopRow(stop: stop, color: LociTheme.dayColor(Int(day.dayNumber)), isEditing: isEditing) { minutes in
          Task { await setDuration(stop, minutes: minutes) }
        }
        .moveDisabled(!canEdit)
        .swipeActions(edge: .trailing) {
          if canEdit {
            Button("Remove", role: .destructive) { Task { await remove(stop) } }
            Button("Replace") { picking = .replace(stopID: stop.id) }.tint(.lociCoral)
          }
        }
        .swipeActions(edge: .leading) {
          if canEdit {
            Button("Rename") {
              renameText = stop.name
              renaming = stop
            }.tint(.lociForest)
          }
        }
      }
      .onMove { from, to in
        var ids = day.stops.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        Task { await reorder(day, ids: ids) }
      }
      if isEditing {
        Button("Add a place to day \(day.dayNumber)", systemImage: "plus") { picking = .add(dayID: day.id) }
      }
    } header: {
      HStack {
        Circle().fill(LociTheme.dayColor(Int(day.dayNumber))).frame(width: 10, height: 10)
        Text("Day \(day.dayNumber)" + (day.cityName.isEmpty || day.cityName == trip.cityName ? "" : " · \(day.cityName)"))
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
    }
  }

  // MARK: - Loading

  /// The phone's copy first, then the server, the plan and the checklists
  /// together. Offline keeps the copy, read-only.
  private func load() async {
    guard !isOffline else { return }
    async let plan: Void = side.loadPlan()
    async let lists: Void = checklist.load()
    await reload()
    _ = await (plan, lists)
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
  private var canEdit: Bool {
    switch loaded {
    case .fresh, nil: true
    case .stale, .missing: false
    }
  }

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

  /// Preference edits run one after another: each needs the `version` the
  /// previous one returned, or the second would be refused as a conflict.
  private func setPreference(_ patch: PreferencePatch) {
    let previous = preferenceQueue
    preferenceQueue = Task {
      await previous?.value
      await sendPreference(patch)
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
    var request = Loci_Trip_AddStopRequest()
    request.tripID = trip.id
    request.dayID = dayID
    request.stop = Self.stop(from: poi, orderIndex: day.stops.count)
    request.baseVersion = trip.version
    await apply("Could not add the place.", request) { await TripAPI.client.addStop(request: $0, headers: [:]) }
  }

  private func replace(_ stopID: String, with poi: Loci_Poi_POIDetailedInfo) async {
    guard let trip, let old = trip.days.flatMap(\.stops).first(where: { $0.id == stopID }) else { return }
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
    var request = Loci_Trip_RemoveStopRequest()
    request.tripID = trip.id
    request.stopID = stop.id
    request.baseVersion = trip.version
    await apply("Could not remove the stop.", request) { await TripAPI.client.removeStop(request: $0, headers: [:]) }
  }

  /// web: routes/trips/[id].tsx share, which also sends share_link_created.
  private func share() async {
    do {
      let response = try await TripAPI.share(tripID: tripID)
      shareURL = URL(string: response.shareURL)
      Analytics.capture(.shareLinkCreated, ["content_type": "trip"])
    } catch {
      if !error.isCancelled { self.error = error.message }
    }
  }
}
