import LociConnectProto
import SwiftUI

/// The result page for one search session: web's `/itinerary`, `/hotels`,
/// `/restaurants` and `/activities` with `?sessionId=&cityName=&domain=`.
///
/// While the search runs it shows tokens as they arrive, then the places as
/// the structured events land. Opened later (a notification tap, a deep link)
/// it restores the session the way web's `restoreOrHydrateSession` does:
/// the live search, then this phone's copy, then GetChatSession, then a re-run.
struct SearchResultsView: View {
  let link: SessionLink

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var controller = SearchSessionController.shared
  @State private var restored: SearchState?
  @State private var isRestoring = false
  @State private var saveStatus: String?
  @State private var error: String?

  /// The live search when it is this session, otherwise what was restored.
  private var state: SearchState? {
    controller.state.sessionId == link.sessionId ? controller.state : restored
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header
        if let state {
          content(state)
        } else if isRestoring {
          ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
        } else {
          unavailable
        }
      }
      .padding(LociTheme.defaultPadding)
    }
    .background(Color.lociPaper.ignoresSafeArea())
    .safeAreaInset(edge: .bottom) {
      // Follow-ups continue this session (web /chat sends sessionId + cityName),
      // so the page keeps showing the live state under the same link.
      if let state, !state.isActive, state.sessionId != nil {
        SearchComposer(placeholder: "Ask a follow-up", cityName: state.cityName, sessionId: state.sessionId) { _ in }
          .padding(LociTheme.defaultPadding).background(.bar)
      }
    }
    .navigationTitle(link.destination.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { toolbar }
    .errorAlert($error)
    .task(id: link.sessionId) { await restoreIfNeeded() }
    .onAppear { controller.viewingSessionId = link.sessionId }
    .onDisappear { if controller.viewingSessionId == link.sessionId { controller.viewingSessionId = nil } }
  }

  // MARK: - Pieces

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let city = state?.cityName ?? link.cityName { Text(city).font(.lociDisplay()).foregroundStyle(Color.lociInk) }
      if let query = state?.query, !query.isEmpty { Text(query).font(.lociBody()).foregroundStyle(Color.lociMutedInk) }
      if let status = statusLine { Text(status).lociCoordStyle() }
    }
  }

  private var statusLine: String? {
    guard let state else { return nil }
    switch state.status {
    case .streaming:
      if let stage = state.progressStage { return state.progressPercent.map { "\(stage) · \($0)%" } ?? stage }
      return "Planning…"
    case .detached: return "Still working — you can leave this screen"
    case .completed: return "\(state.places.count) places"
    case .failed, .idle: return nil
    }
  }

  @ViewBuilder private func content(_ state: SearchState) -> some View {
    if case .failed(let message) = state.status {
      failure(message, query: state.query)
    }

    if let itinerary = state.itinerary, state.destination == .itinerary, !itinerary.itineraryResponse.itineraryName.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text(itinerary.itineraryResponse.itineraryName).font(.lociTitle())
        if !itinerary.itineraryResponse.overallDescription.isEmpty {
          Text(itinerary.itineraryResponse.overallDescription).font(.lociBody())
        }
      }
      .lociCard()
    } else if !state.text.isEmpty, state.places.isEmpty {
      // Tokens as they arrive, until a structured result replaces them.
      Text(state.text).font(.lociBody()).foregroundStyle(Color.lociInk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lociCard()
        .animation(reduceMotion ? nil : LociTheme.reducedFade, value: state.text)
    } else if state.isActive, state.places.isEmpty {
      SkeletonCards()
    }

    LazyVStack(spacing: 12) {
      ForEach(Array(state.places.enumerated()), id: \.offset) { _, poi in
        POICardView(poi: poi).transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(reduceMotion ? LociTheme.reducedFade : LociTheme.resultArrive, value: state.places.count)

    if state.status == .completed, state.places.isEmpty, state.destination != .itinerary {
      Text("The list finished on the server but didn't reach this phone.").foregroundStyle(Color.lociMutedInk)
      rerunButton(query: state.query)
    }
  }

  private func failure(_ message: String, query: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Color.lociDestructive)
      if !query.isEmpty { rerunButton(query: query) }
    }
    .lociCard()
  }

  private func rerunButton(query: String) -> some View {
    Button("Run the search again") { Task { await rerun(query) } }.buttonStyle(.borderedProminent).tint(.lociForest)
  }

  private var unavailable: some View {
    ContentUnavailableView {
      Label("Search not found", systemImage: "magnifyingglass")
    } description: {
      Text("This search finished on another device or has expired.")
    }
  }

  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    if let state, state.isActive, controller.state.sessionId == link.sessionId {
      ToolbarItem(placement: .primaryAction) {
        Button("Stop", systemImage: "stop.circle") { controller.stop() }
      }
    } else if let state, state.status == .completed, state.destination == .itinerary {
      ToolbarItem(placement: .primaryAction) {
        Button(saveStatus ?? "Save", systemImage: "bookmark") { Task { await save(state) } }.disabled(saveStatus != nil)
      }
    }
    if let state, state.hasResult {
      ToolbarItem(placement: .secondaryAction) {
        ShareLink(item: ItineraryShareText.text(for: state)) { Label("Share", systemImage: "square.and.arrow.up") }
      }
    }
  }

  // MARK: - Actions

  private func restoreIfNeeded() async {
    guard controller.state.sessionId != link.sessionId, restored == nil else { return }
    isRestoring = true
    restored = await controller.state(for: link)
    isRestoring = false
  }

  private func rerun(_ query: String) async {
    do {
      try await controller.start(query: query, cityName: state?.cityName ?? link.cityName)
    } catch { self.error = error.userMessage }
  }

  /// ItineraryService.BookmarkItinerary with the fields web's /itinerary Save sends.
  private func save(_ state: SearchState) async {
    var request = Loci_Itinerary_BookmarkRequest()
    let city = state.cityData?.city ?? state.cityName ?? ""
    let name = state.itinerary?.itineraryResponse.itineraryName ?? ""
    request.primaryCityName = city
    request.title = name.isEmpty ? "\(city) itinerary" : name
    request.description_p = state.cityData.map { $0.description_p.isEmpty ? "Itinerary for \(city)" : $0.description_p } ?? "Itinerary for \(city)"
    request.tags = []
    request.isPublic = false
    if let sessionId = state.sessionId { request.sessionID = sessionId }
    do {
      _ = try await rpc("Could not save the itinerary.", request) {
        await Loci_Itinerary_ItineraryServiceClient(client: ConnectTransport.shared.protocolClient).bookmarkItinerary(request: $0, headers: [:])
      }
      saveStatus = "Saved"
    } catch { self.error = error.userMessage }
  }
}

extension SearchDestination {
  var title: String {
    switch self {
    case .itinerary: "Itinerary"
    case .hotels: "Hotels"
    case .restaurants: "Restaurants"
    case .activities: "Activities"
    }
  }
}

/// Placeholder cards while the first results are on their way.
struct SkeletonCards: View {
  var body: some View {
    VStack(spacing: 12) {
      ForEach(0..<3, id: \.self) { _ in
        RoundedRectangle(cornerRadius: LociTheme.cornerRadius).fill(Color.lociMuted).frame(height: 96)
      }
    }
    .redacted(reason: .placeholder)
    .accessibilityLabel("Loading results")
  }
}

/// Plain-text share of a result, grouped by day like web's share text,
/// ending with "Generated from Loci".
enum ItineraryShareText {
  static func text(for state: SearchState) -> String {
    var lines: [String] = []
    let city = state.cityName ?? state.cityData?.city ?? ""
    if let name = state.itinerary?.itineraryResponse.itineraryName, !name.isEmpty { lines.append(name) } else if !city.isEmpty {
      lines.append("\(state.destination.title) in \(city)")
    }
    let byDay = Dictionary(grouping: state.places) { $0.hasDay ? Int($0.day) : 0 }
    for day in byDay.keys.sorted() {
      lines.append("")
      if day > 0 { lines.append("Day \(day)") }
      for poi in byDay[day] ?? [] {
        lines.append("• \(poi.name)" + (poi.address.isEmpty ? "" : " — \(poi.address)"))
      }
    }
    lines.append("")
    lines.append("Generated from Loci")
    return lines.joined(separator: "\n")
  }
}
