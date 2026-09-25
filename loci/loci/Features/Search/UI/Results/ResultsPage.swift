import LociConnectProto
import SwiftUI

/// The body of the agent bubble on a result page, in web's `/itinerary`
/// order: city header, forecast and money, status rail, title and summary,
/// map hero, the days, "More to explore", the Trip Kit. Tokens are never
/// shown; the structured events are the answer.
struct ResultsPage: View {
  let state: SearchState
  var onRerun: (String) -> Void = { _ in }

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

  private var groups: [DayGroup] { state.dayGroups }
  private var extras: [Loci_Poi_POIDetailedInfo] { state.extras }
  private var sequence: [String: Int] { DayGrouping.sequence(groups) }
  private var showsDays: Bool { state.destination == .itinerary }
  private var visibleGroups: [DayGroup] { showAllDays ? groups : Array(groups.prefix(DayGrouping.initialDays)) }
  private var hiddenDays: Int { max(groups.count - DayGrouping.initialDays, 0) }
  private var cityName: String { state.cityData?.city ?? state.cityName ?? "" }
  private var title: String {
    if let name = state.itinerary?.itineraryResponse.itineraryName, !name.isEmpty { return name }
    return state.destination.bookmarkTitle(city: cityName)
  }

  private var summary: String { state.itinerary?.itineraryResponse.overallDescription ?? "" }
  private var arrival: AnyTransition { reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity) }
  private var mapData: ResultsMapData {
    ResultsMapData(groups: groups, extras: extras, sequence: sequence, showsDays: showsDays, alerts: side.localContext?.alerts ?? [])
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let message = state.failureMessage { FailureRail(message: message, canRetry: !state.query.isEmpty) { onRerun(state.query) } }
      ResultsHeader(city: state.cityData, fallbackCityName: state.cityName)
      LocalContextStrip(context: side.localContext, fxRates: side.fxRates)
      CacheChip(loaded: side.contextLoaded)
      if state.status != .failed(state.failureMessage ?? "") || state.hasResult {
        StatusRail(state: state)
      }
      if state.hasResult {
        results.transition(arrival)
      } else if state.isActive {
        SkeletonCards()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(reduceMotion ? LociTheme.reducedFade : LociTheme.resultArrive, value: state.hasResult)
    .task(id: contextKey) {
      guard let city = state.cityData, city.hasCenterLatitude, city.hasCenterLongitude else { return }
      await side.loadContext(latitude: city.centerLatitude, longitude: city.centerLongitude)
    }
    .sheet(item: $detail) { stop in PlaceDetailSheet(stop: stop, destination: state.destination, cityName: cityName) }
    .fullScreenCover(isPresented: $showFullMap) {
      FullMapView(
        data: mapData,
        groups: groups,
        sequence: sequence,
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

  @ViewBuilder private var results: some View {
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
    if !mapData.isEmpty {
      ResultsMapCard(data: mapData, selectedID: selectedID) { showFullMap = true }
    }
    ForEach(visibleGroups, id: \.number) { group in
      DaySection(group: group, sequence: sequence, destination: state.destination, showsDayLabel: showsDays, selectedID: $selectedID) { detail = $0 }
        .id(group.number == 1 ? Anchor.days : "results-day-\(group.number)")
    }
    if !showAllDays, hiddenDays > 0 {
      Button("Show the rest of the trip (\(hiddenDays) more \(hiddenDays == 1 ? "day" : "days"))", systemImage: "chevron.down") {
        withAnimation(reduceMotion ? LociTheme.reducedFade : LociTheme.defaultSpring) { showAllDays = true }
      }
      .buttonStyle(MusePillButtonStyle())
    }
    if !extras.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("More to explore").font(.lociHeadline(15)).foregroundStyle(Color.lociInk)
        ForEach(Array(extras.enumerated()), id: \.element.stableID) { offset, stop in
          StopCard(
            stop: stop,
            index: (sequence.values.max() ?? 0) + offset + 1,
            color: LociTheme.ungroupedColor,
            destination: state.destination,
            isSelected: selectedID == stop.stableID
          ) {
            selectedID = stop.stableID
            detail = stop
          }
        }
      }
    }
    if !state.isActive, !groups.isEmpty {
      TripKitView(groups: groups, cityName: cityName, title: title, summary: summary, side: side).id(Anchor.kit)
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
      if state.plannedDays > 0, state.destination == .itinerary { Text("· \(state.plannedDays) days planned").lociCoordStyle(10) }
    }
    .accessibilityElement(children: .combine)
  }

  private var text: String {
    let count = state.places.count
    switch state.phase {
    case .skeleton:
      if let stage = state.progressStage, !stage.isEmpty { return stage }
      return state.destination == .itinerary ? "Sketching your days…" : "Finding \(state.destination.title.lowercased())…"
    case .enriching:
      let photos = state.places.filter(\.hasPhoto).count
      return photos < count ? "Adding photos \(photos)/\(count)" : "Finishing up…"
    case .done:
      return state.destination == .itinerary ? "Itinerary ready · \(count) stops" : "\(count) \(state.destination.title.lowercased()) found"
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
