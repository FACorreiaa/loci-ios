import LociConnectProto
import SwiftUI

/// The body of the agent bubble on a result page, in web's `/itinerary`
/// order: city header, forecast and money, status rail, title and summary,
/// map hero, the days, "More to explore", the Trip Kit. Tokens are never
/// shown; the structured events are the answer.
struct ResultsPage: View {
  let state: SearchState
  var onRerun: (String) -> Void = { _ in }
  /// False for one city of a multi-city trip: its trip spans every city, so
  /// that page stays as generated and the trip is edited from Trips.
  var editsTrip = true

  /// Scroll anchors, used by the design preview.
  enum Anchor {
    static let days = "results-days"
    static let kit = "results-kit"
  }

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var side = ResultsSideData()
  @State private var selectedID: String?
  @State private var detail: Loci_Poi_POIDetailedInfo?
  @State private var showFullMap = false
  @State private var showAllDays = false
  @State private var editingTrip = false
  /// Places waved away with "Not for me" on this page (stable ids).
  @State private var dismissed: Set<String> = []
  /// The trip the server saved for this itinerary: once found, the page is a
  /// view of it, and edits made here are edits to it.
  @State private var edit = TripEditSession()
  @State private var eatingNear: Loci_Poi_POIDetailedInfo?
  @State private var searchingFor: TripDayRef?
  @State private var pastingFor: TripDayRef?
  @Environment(\.scenePhase) private var scenePhase

  /// The lists derived from the places, built once per body: each is a pass
  /// over every stop, and the page reads them many times.
  private struct Derived {
    let groups: [DayGroup]
    let extras: [Loci_Poi_POIDetailedInfo]
    let sequence: [String: Int]
    let mapData: ResultsMapData
    /// "More to explore" numbers on from the last numbered stop.
    let extrasStart: Int
    /// Set when the days come from the trip rather than the generation.
    var backed: TripBackedDays?
  }

  /// The page follows the trip only for a finished single itinerary.
  private var followsTrip: Bool { editsTrip && showsDays && !state.isActive && !state.isMultiCity }
  private var tripKey: String { followsTrip ? "\(state.savedTripID ?? "")|\(state.sessionId ?? "")" : "" }

  private var showsDays: Bool { state.destination == .itinerary }

  /// "Not for me" for places Loci recommended; nil for the rest, so their
  /// cards offer nothing the server would reject.
  private func dismissHandler(_ stop: Loci_Poi_POIDetailedInfo) -> (() -> Void)? {
    guard let outcome = stop.outcome(.dismissed) else { return nil }
    return {
      OutcomeAPI.send(outcome)
      if selectedID == stop.stableID { selectedID = nil }
      withAnimation(reduceMotion ? LociTheme.reducedFade : LociTheme.defaultSpring) { _ = dismissed.insert(stop.stableID) }
    }
  }

  private var cityName: String { state.cityData?.city ?? state.cityName ?? "" }
  private var title: String {
    // A gastronomy search's heading is the section's own.
    if state.isGastronomySearch { return "" }
    if let name = state.itinerary?.itineraryResponse.itineraryName, !name.isEmpty { return name }
    return state.destination.bookmarkTitle(city: cityName)
  }

  private var summary: String { state.itinerary?.itineraryResponse.overallDescription ?? "" }
  private var arrival: AnyTransition { reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity) }

  private func derive() -> Derived {
    let backed = followsTrip ? edit.trip.map { TripBackedDays.build(trip: $0, generated: state.places + state.extras) } : nil
    let kept = ResultsDismissal.apply(
      groups: backed?.groups ?? state.dayGroups,
      extras: backed?.extras ?? state.extras,
      dismissed: dismissed,
      showsDays: showsDays
    )
    let groups = kept.groups
    let extras = kept.extras
    let sequence = DayGrouping.sequence(groups)
    return Derived(
      groups: groups,
      extras: extras,
      sequence: sequence,
      mapData: ResultsMapData(groups: groups, extras: extras, sequence: sequence, showsDays: showsDays, alerts: side.localContext?.alerts ?? []),
      extrasStart: (sequence.values.max() ?? 0) + 1,
      backed: backed
    )
  }

  // MARK: - The trip behind the page

  /// Links for every itinerary stop; edits only where the trip is the viewer's own.
  private func menu(for stop: Loci_Poi_POIDetailedInfo, in derived: Derived) -> StopMenu? {
    guard showsDays else { return nil }
    var menu = StopMenu()
    menu.googleURL = GoogleMapsRoute.placeURL(name: stop.name, city: cityName)
    menu.onGoogle = { Analytics.capture(.itineraryGoogleLinkOpened, ["source": "stop_card"]) }
    menu.onEatNearby = { eatingNear = stop }
    guard edit.canEdit, !edit.isBusy, let backed = derived.backed, let ref = backed.refs[stop.stableID] else { return menu }
    if ref.index > 0 { menu.onMoveUp = { change("move") { await edit.nudge(stopID: ref.stopID, up: true) } } }
    if ref.index < ref.count - 1 { menu.onMoveDown = { change("move") { await edit.nudge(stopID: ref.stopID, up: false) } } }
    menu.moveTargets = backed.days.filter { $0.id != ref.dayID }.map { day in
      StopMenu.MoveTarget(id: day.id, label: "Day \(day.number)") {
        change("move_day") { await edit.move(stopID: ref.stopID, toDayID: day.id) }
      }
    }
    menu.onRemove = { change("remove") { await edit.remove(stopID: ref.stopID) } }
    return menu
  }

  private func change(_ action: String, _ run: @escaping () async -> Bool) {
    Task {
      let stuck = await run()
      if stuck { Analytics.capture(.itineraryStopEdited, ["action": action]) }
    }
  }

  private func add(_ stop: Loci_Trip_TripStop, to dayID: String, after stopID: String? = nil, method: String) async -> Bool {
    let stuck = await edit.add(stop, dayID: dayID, afterStopID: stopID)
    if stuck { Analytics.capture(.itineraryStopAdded, ["method": method, "known_place": !stop.poiID.isEmpty]) }
    return stuck
  }

  /// Suggestions and "Add a place" under a day the viewer can edit.
  private func dayFooter(_ group: DayGroup, in derived: Derived) -> AnyView? {
    guard edit.canEdit, let backed = derived.backed, let day = backed.days.first(where: { $0.number == group.number }) else { return nil }
    let onTrip = backed.groups.flatMap(\.stops)
    return AnyView(
      VStack(alignment: .leading, spacing: 8) {
        DaySuggestionsRow(
          dayNumber: day.number,
          dayStops: group.stops,
          onTrip: onTrip,
          extras: backed.extras,
          isBusy: edit.isBusy
        ) { place, fromExtras in
          Task {
            let stop = TripEdits.stop(from: place)
            let stuck = await edit.add(stop, dayID: day.id)
            if stuck {
              Analytics.capture(
                .itineraryStopAdded,
                ["method": "suggestion", "known_place": !stop.poiID.isEmpty, "source": fromExtras ? "extras" : "nearby"]
              )
            }
          }
        }
        Menu {
          Button("Search by name", systemImage: "magnifyingglass") { searchingFor = day }
          Button("Paste a link", systemImage: "link") { pastingFor = day }
        } label: {
          Label("Add a place to day \(day.number)", systemImage: "plus")
        }
        .buttonStyle(MusePillButtonStyle())
        .disabled(edit.isBusy)
      }
    )
  }

  private var notice: Binding<String?> { Binding(get: { edit.notice }, set: { edit.notice = $0 }) }

  private func loadTrip() async {
    // Signed out there is no trip to find, and the page stays as generated.
    guard !tripKey.isEmpty, await AuthSessionManager.shared.currentUserID != nil else { return }
    await edit.load(tripID: state.savedTripID, sessionID: state.sessionId)
  }

  /// Someone else may have changed the trip meanwhile: a co-planner, the web,
  /// Telegram.
  private func refreshTrip(_ phase: ScenePhase) {
    guard phase == .active, let trip = edit.trip, !edit.isBusy else { return }
    Task { await edit.load(tripID: trip.id, sessionID: nil) }
  }

  private func eatSheet(_ anchor: Loci_Poi_POIDetailedInfo, _ derived: Derived) -> some View {
    let ref = edit.canEdit ? derived.backed?.refs[anchor.stableID] : nil
    var onAdd: ((Loci_Poi_POIDetailedInfo) async -> Bool)?
    if let ref {
      onAdd = { place in await add(TripEdits.stop(from: place), to: ref.dayID, after: ref.stopID, method: "eat_nearby") }
    }
    return EatNearbySheet(anchor: anchor, cityName: cityName, onTrip: derived.groups.flatMap(\.stops), onAdd: onAdd)
  }

  private func searchSheet(_ day: TripDayRef) -> some View {
    PlacePicker(
      cityName: cityName,
      onSelect: { place in Task { _ = await add(TripEdits.stop(from: place), to: day.id, method: "search") } },
      onAddUnknown: { name in Task { _ = await add(TripEdits.stop(named: name), to: day.id, method: "named") } }
    )
  }

  private func pasteSheet(_ day: TripDayRef) -> some View {
    PasteLinkSheet(cityName: cityName, dayNumber: day.number) { place in
      await add(TripEdits.stop(from: place), to: day.id, method: "link")
    }
  }

  var body: some View {
    let derived = derive()
    VStack(alignment: .leading, spacing: 16) {
      if let message = state.failureMessage { FailureRail(message: message, canRetry: !state.query.isEmpty) { onRerun(state.query) } }
      ResultsHeader(city: state.cityData, fallbackCityName: state.cityName)
      LocalContextStrip(context: side.localContext, fxRates: side.fxRates)
      CacheChip(loaded: side.contextLoaded)
      if state.status != .failed(state.failureMessage ?? "") || state.hasResult {
        StatusRail(state: state)
      }
      if state.hasResult {
        results(derived).transition(arrival)
      } else if state.isActive {
        SkeletonCards()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(reduceMotion ? LociTheme.reducedFade : LociTheme.resultArrive, value: state.hasResult)
    .animation(reduceMotion ? LociTheme.reducedFade : LociTheme.defaultSpring, value: edit.trip?.version)
    .task(id: contextKey) {
      guard let city = state.cityData, city.hasCenterLatitude, city.hasCenterLongitude else { return }
      await side.loadContext(latitude: city.centerLatitude, longitude: city.centerLongitude)
    }
    .sheet(item: $detail) { stop in PlaceDetailSheet(stop: stop, destination: state.destination, cityName: cityName) }
    .task(id: tripKey) { await loadTrip() }
    .onChange(of: scenePhase) { _, phase in refreshTrip(phase) }
    .errorAlert(notice)
    .sheet(item: $eatingNear) { eatSheet($0, derived) }
    .sheet(item: $searchingFor) { searchSheet($0) }
    .sheet(item: $pastingFor) { pasteSheet($0) }
    .onChange(of: detail?.stableID) { _, opened in
      guard opened != nil, let stop = detail else { return }
      OutcomeAPI.send(stop.outcome(.opened))
    }
    .fullScreenCover(isPresented: $showFullMap) {
      FullMapView(
        data: derived.mapData,
        groups: derived.groups,
        sequence: derived.sequence,
        destination: state.destination,
        showsDays: showsDays,
        title: cityName.isEmpty ? state.destination.title : cityName,
        selectedID: $selectedID
      )
    }
  }

  private var contextKey: String {
    guard let city = state.cityData, city.hasCenterLatitude else { return "" }
    return "\(city.centerLatitude),\(city.centerLongitude)"
  }

  @ViewBuilder private func results(_ derived: Derived) -> some View {
    let groups = derived.groups
    // A page that follows its trip shows every day: a stop moved to day 3
    // must not vanish behind "Show the rest".
    let unfolded = showAllDays || derived.backed != nil
    let visibleGroups = unfolded ? groups : Array(groups.prefix(DayGrouping.initialDays))
    let hiddenDays = max(groups.count - DayGrouping.initialDays, 0)
    let dayDismiss: ((Loci_Poi_POIDetailedInfo) -> (() -> Void)?)? = showsDays ? nil : { stop in dismissHandler(stop) }
    if !title.isEmpty || !summary.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        if !title.isEmpty { Text(title).font(.lociTitle(22)).foregroundStyle(Color.lociInk) }
        if !summary.isEmpty { Text(summary).font(.lociBody(15)).foregroundStyle(Color.lociMutedInk) }
      }
    }
    if let tripID = state.savedTripID, !state.isActive {
      TripSavedBanner(cityName: cityName) { editingTrip = true }
        .sheet(isPresented: $editingTrip) { TripEditorSheet(tripID: tripID) }
    }
    if !derived.mapData.isEmpty {
      ResultsMapCard(data: derived.mapData, selectedID: selectedID) { showFullMap = true }
    }
    ForEach(visibleGroups, id: \.number) { group in
      DaySection(
        group: group,
        sequence: derived.sequence,
        destination: state.destination,
        showsDayLabel: showsDays,
        route: showsDays ? state.accessibleRoutes[group.number] : nil,
        selectedID: $selectedID,
        dismissAction: dayDismiss,
        menu: { menu(for: $0, in: derived) },
        footer: dayFooter(group, in: derived),
      ) { detail = $0 }
        .id(group.number == 1 ? Anchor.days : "results-day-\(group.number)")
    }
    if !unfolded, hiddenDays > 0 {
      Button("Show the rest of the trip (\(hiddenDays) more \(hiddenDays == 1 ? "day" : "days"))", systemImage: "chevron.down") {
        withAnimation(reduceMotion ? LociTheme.reducedFade : LociTheme.defaultSpring) { showAllDays = true }
      }
      .buttonStyle(MusePillButtonStyle())
    }
    if !derived.extras.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("More to explore").font(.lociHeadline(15)).foregroundStyle(Color.lociInk)
        ForEach(Array(derived.extras.enumerated()), id: \.element.stableID) { offset, stop in
          StopCard(
            stop: stop,
            index: derived.extrasStart + offset,
            color: LociTheme.ungroupedColor,
            destination: state.destination,
            isSelected: selectedID == stop.stableID,
            onDismiss: dismissHandler(stop),
          ) {
            selectedID = stop.stableID
            detail = stop
          }
        }
      }
    }
    if let gastronomy = state.gastronomy {
      GastronomySection(gastronomy: gastronomy, compact: !state.isGastronomySearch)
    }
    if !state.isActive, !groups.isEmpty {
      TripKitView(
        groups: groups,
        cityName: cityName,
        title: title,
        summary: summary,
        side: side,
        sessionID: state.sessionId,
        tripID: state.savedTripID
      )
      .id(Anchor.kit)
    }
  }
}

/// Web's "Trip saved · Edit trip" CTA: the server kept this itinerary as a trip.
struct TripSavedBanner: View {
  let cityName: String
  let onEdit: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "suitcase.fill").foregroundStyle(Color.lociForest).accessibilityHidden(true)
      Text(cityName.isEmpty ? "Trip saved" : "Trip saved · \(cityName)")
        .font(.lociCaption(14).weight(.semibold)).foregroundStyle(Color.lociInk)
      Spacer(minLength: 8)
      Button("Edit trip", action: onEdit)
        .font(.lociCaption(14).weight(.semibold))
        .buttonStyle(.bordered)
        .tint(Color.lociForest)
    }
    .padding(12)
    .background(Color.lociSage.opacity(0.5), in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}

/// The trip editor in its own stack, over a results page.
private struct TripEditorSheet: View {
  let tripID: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      TripEditorView(tripID: tripID)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
    }
  }
}

/// Web's status rail: what the page is doing, in one line.
struct StatusRail: View {
  let state: SearchState

  var body: some View {
    HStack(spacing: 8) {
      if state.isActive { ProgressView().controlSize(.small) }
      Text(text).lociCoordStyle(10)
      if state.plannedDays > 0, state.destination == .itinerary { Text("· ^[\(state.plannedDays) day](inflect: true) planned").lociCoordStyle(10) }
    }
    .accessibilityElement(children: .combine)
  }

  private var text: AttributedString {
    let count = state.places.count
    if state.isGastronomySearch {
      if let dishes = state.gastronomy?.dishes.count { return AttributedString(localized: "Local food ready · ^[\(dishes) dish](inflect: true)") }
      return AttributedString(localized: state.isActive ? "Tasting the local food…" : "No typical food found")
    }
    switch state.phase {
    case .skeleton:
      if let stage = state.progressStage, !stage.isEmpty { return AttributedString(stage) }
      return state.destination == .itinerary
        ? AttributedString(localized: "Sketching your days…")
        : AttributedString(localized: "Finding \(state.destination.title.lowercased())…")
    case .enriching:
      let photos = state.places.count(where: \.hasPhoto)
      return photos < count ? AttributedString(localized: "Adding photos \(photos)/\(count)") : AttributedString(localized: "Finishing up…")
    case .done:
      return switch state.destination {
      case .itinerary: AttributedString(localized: "Itinerary ready · ^[\(count) stop](inflect: true)")
      case .hotels: AttributedString(localized: "^[\(count) hotel](inflect: true) found")
      case .restaurants: AttributedString(localized: "^[\(count) restaurant](inflect: true) found")
      case .activities: AttributedString(localized: "^[\(count) activity](inflect: true) found")
      }
    }
  }
}

/// Failed with or without results: web shows the error above what it has and
/// offers a retry. Quota messages carry the link to the plans.
struct FailureRail: View {
  let message: String
  let canRetry: Bool
  var onRetry: () -> Void

  private var isQuota: Bool { message.localizedCaseInsensitiveContains("limit") || message.localizedCaseInsensitiveContains("free searches") }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Color.lociDestructive).font(.lociCaption(13))
      HStack(spacing: 8) {
        if canRetry { Button("Run the search again", action: onRetry).buttonStyle(MusePillButtonStyle()) }
        if isQuota { Link("See Pro plans", destination: ProGate.pricingURL).font(.lociCaption(12)) }
      }
    }
    .padding(10)
    .background(Color.lociDestructive.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}
