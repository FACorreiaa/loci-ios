import Connect
import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// The trip editor (web: /trips/:id). Every edit is one TripService RPC that
/// returns the new TripDraft, whose `version` is the next `baseVersion`, so a
/// stale edit from another device is refused by the server rather than merged.
struct TripEditorView: View {
  let tripID: String

  @State private var trip: Loci_Trip_TripDraft?
  @State private var loaded: Loaded<Loci_Trip_TripDraft>?
  @State private var isEditing = false
  @State private var renaming: Loci_Trip_TripStop?
  @State private var renameText = ""
  @State private var picking: PickerTarget?
  @State private var shareURL: URL?
  @State private var exportedFile: URL?
  @State private var packing: Loci_Trip_SuggestPackingResponse?
  @State private var calendarStatus: String?
  @State private var error: String?

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
          constraintsSection(trip)
          ForEach(trip.days, id: \.id) { day in daySection(day, trip: trip) }
          if !trip.legs.isEmpty { legsSection(trip.legs) }
          toolsSection(trip)
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

  private func constraintsSection(_ trip: Loci_Trip_TripDraft) -> some View {
    Section("Pace") {
      if let loaded, loaded.staleSince != nil {
        CacheChip(loaded: loaded)
        if !canEdit { Text("Connect to edit").lociCoordStyle(10) }
      }
      Picker("Pace", selection: Binding(get: { trip.constraints.pace }, set: { pace in Task { await setPace(pace) } })) {
        Text("Relaxed").tag(Loci_Trip_TripPace.relaxed)
        Text("Moderate").tag(Loci_Trip_TripPace.moderate)
        Text("Packed").tag(Loci_Trip_TripPace.packed)
      }
      .pickerStyle(.segmented)
    }
  }

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
        if day.hasDate { Spacer(); Text(day.date.date, style: .date) }
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

  private func toolsSection(_ trip: Loci_Trip_TripDraft) -> some View {
    Section("Take it with you") {
      Button("Add to Apple Calendar", systemImage: "calendar.badge.plus") { Task { await addToCalendar(trip) } }
      if let calendarStatus { Text(calendarStatus).font(.lociCaption()).foregroundStyle(Color.lociMutedInk) }
      Menu {
        Button("Calendar file (.ics)") { Task { await export(.ics) } }
        Button("PDF") { Task { await export(.pdf) } }
        Button("Markdown") { Task { await export(.markdown) } }
      } label: {
        Label("Export", systemImage: "arrow.down.doc")
      }
      if let exportedFile { ShareLink(item: exportedFile) { Label("Share the export", systemImage: "square.and.arrow.up") } }
      Button("What to pack", systemImage: "backpack") { Task { await suggestPacking() } }
      if let packing {
        ForEach(packing.suggestions, id: \.text) { item in
          Label(item.text, systemImage: item.essential ? "checkmark.seal" : "circle").font(.lociCaption())
        }
        if packing.weatherIsEstimated { Text("Based on typical weather, not a forecast.").font(.lociCaption()).foregroundStyle(Color.lociMutedInk) }
      }
    }
  }

  // MARK: - RPCs

  /// The phone's copy first, then the server. Offline keeps the copy, read-only.
  private func load() async {
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

  /// Run an edit and adopt the trip the server returns; the copy follows it.
  private func apply<Input: Sendable>(
    _ fallback: String,
    _ request: Input,
    _ call: @escaping @Sendable (Input) async -> ResponseMessage<Loci_Trip_TripDraft>
  ) async {
    do {
      let draft = try await rpc(fallback, request, call)
      trip = draft
      loaded = .fresh(draft)
      try? await LocalCache.shared.put(draft, kind: .trip, id: tripID)
    } catch { self.error = error.userMessage }
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

  private func setPace(_ pace: Loci_Trip_TripPace) async {
    guard let trip else { return }
    var request = Loci_Trip_SetConstraintRequest()
    request.tripID = trip.id
    request.constraints = trip.constraints
    request.constraints.pace = pace
    request.baseVersion = trip.version
    await apply("Could not change the pace.", request) { await TripAPI.client.setConstraint(request: $0, headers: [:]) }
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

  private static func stop(from poi: Loci_Poi_POIDetailedInfo, orderIndex: Int) -> Loci_Trip_TripStop {
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

  private func share() async {
    var request = Loci_Trip_ShareTripRequest()
    request.tripID = tripID
    request.isPublic = true
    do {
      let response = try await rpc("Could not create a share link.", request) { await TripAPI.client.shareTrip(request: $0, headers: [:]) }
      shareURL = URL(string: response.shareURL)
    } catch { self.error = error.userMessage }
  }

  private func export(_ format: Loci_Trip_ExportFormat) async {
    var request = Loci_Trip_ExportTripRequest()
    request.tripID = tripID
    request.format = format
    do {
      let response = try await rpc("Could not export the trip.", request) { await TripAPI.client.exportTrip(request: $0, headers: [:]) }
      let name = response.filename.isEmpty ? "trip.\(format == .ics ? "ics" : format == .pdf ? "pdf" : "md")" : response.filename
      let url = FileManager.default.temporaryDirectory.appending(path: name)
      try response.data.write(to: url, options: .atomic)
      exportedFile = url
    } catch { self.error = error.userMessage }
  }

  private func suggestPacking() async {
    var request = Loci_Trip_SuggestPackingRequest()
    request.tripID = tripID
    do {
      packing = try await rpc("Could not suggest packing.", request) { await TripAPI.client.suggestPacking(request: $0, headers: [:]) }
    } catch { self.error = error.userMessage }
  }

  private func addToCalendar(_ trip: Loci_Trip_TripDraft) async {
    do {
      guard try await AppleCalendar.shared.requestAccess() else {
        calendarStatus = "Calendar access is off in Settings."
        return
      }
      try AppleCalendar.shared.writeTrip(trip)
      calendarStatus = "Added to the Loci calendar on this iPhone."
    } catch { self.error = error.userMessage }
  }
}

struct StopRow: View {
  let stop: Loci_Trip_TripStop
  let color: Color
  let isEditing: Bool
  let onDuration: (Int) -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Text("\(stop.orderIndex + 1)").lociCoordStyle(11).frame(width: 20)
      VStack(alignment: .leading, spacing: 3) {
        Text(stop.name).font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
        if !stop.notes.isEmpty { Text(stop.notes).font(.lociCaption()).foregroundStyle(Color.lociMutedInk).lineLimit(2) }
        if isEditing {
          Stepper(
            "\(stop.hasDurationMinutes ? Int(stop.durationMinutes) : 60) min",
            value: Binding(get: { stop.hasDurationMinutes ? Int(stop.durationMinutes) : 60 }, set: onDuration),
            in: 15...480,
            step: 15
          ).font(.lociCaption())
        } else if stop.hasDurationMinutes {
          Text("\(stop.durationMinutes) min").lociCoordStyle(10)
        }
      }
    }
    .listRowBackground(Color.lociCard)
  }
}

/// Search canonical places in the trip's city (web: PlacePicker →
/// PoiService.SearchPOI{query, cityName, searchType: "semantic"}).
struct PlacePicker: View {
  let cityName: String
  let onSelect: (Loci_Poi_POIDetailedInfo) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var results: [Loci_Poi_POIDetailedInfo] = []
  @State private var isSearching = false
  @State private var error: String?

  var body: some View {
    NavigationStack {
      List {
        ForEach(results, id: \.stableID) { poi in
          Button {
            onSelect(poi)
            dismiss()
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(poi.name).foregroundStyle(Color.lociInk)
              if !poi.category.isEmpty { Text(poi.category).lociCoordStyle(10) }
            }
          }
        }
      }
      .overlay { if isSearching { ProgressView() } }
      .searchable(text: $query, prompt: cityName.isEmpty ? "Search places" : "Search places in \(cityName)")
      .onSubmit(of: .search) { Task { await search() } }
      .navigationTitle("Add a place").navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Cancel") { dismiss() } }
      .errorAlert($error)
    }
  }

  private func search() async {
    let text = query.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return }
    isSearching = true
    defer { isSearching = false }
    var request = Loci_Poi_SearchPOIRequest()
    request.query = text
    request.cityName = cityName
    request.searchType = "semantic"
    do {
      results = Array(
        try await rpc("Search failed.", request) {
          await Loci_Poi_PoiserviceClient(client: ConnectTransport.shared.protocolClient).searchPoi(request: $0, headers: [:])
        }.pois.prefix(6)
      )
    } catch { self.error = error.userMessage }
  }
}
