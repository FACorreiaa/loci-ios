import LociConnectProto
import SwiftUI

/// The result page for one search session: web's `/itinerary`, `/hotels`,
/// `/restaurants` and `/activities` with `?sessionId=&cityName=&domain=`.
///
/// While the search runs it shows tokens as they arrive, then the places as
/// the structured events land. Opened later (a notification tap, a deep link)
/// it restores the session the way web's `restoreOrHydrateSession` does:
/// the live search, then this phone's copy, then GetChatSession, then a re-run.
///
/// Drawn as a Muse chat (apps/_reviews/muse-chat-contract.md): the query is the
/// user bubble, the answer and its places are the agent bubble.
struct SearchResultsView: View {
  let link: SessionLink

  @Environment(\.dismiss) private var dismiss
  private let controller = SearchSessionController.shared
  private let router = AppRouter.shared
  @State private var restored: SearchState?
  @State private var isRestoring = false
  @State private var saveStatus: String?
  @State private var error: String?
  @State private var isComposing = false
  @State private var flash: MuseActivity.Flash?

  /// The live search when it is this session, otherwise what was restored.
  private var state: SearchState? {
    controller.state.sessionId == link.sessionId ? controller.state : restored
  }

  /// This page is showing the search that is streaming right now.
  private var isLive: Bool {
    guard let state else { return false }
    return state.isActive && controller.state.sessionId == link.sessionId
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        if let state {
          SearchTranscript(state: state, caption: caption) { query in Task { await rerun(query) } }
          actions(state)
        } else if isRestoring {
          ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
        } else {
          unavailable
        }
      }
      .padding(.horizontal, LociTheme.defaultPadding)
      .padding(.vertical, 12)
    }
    .background(Color.museCanvas.ignoresSafeArea())
    .safeAreaInset(edge: .top, spacing: 0) {
      MuseChatHeader(
        activity: .resolve(state, flash: flash, isListening: isComposing),
        leadingSystemImage: "chevron.left",
        leadingLabel: "Back",
        onLeading: { dismiss() },
        onNewChat: newChat
      )
    }
    .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
    .navigationTitle(link.destination.title)
    .toolbarVisibility(.hidden, for: .navigationBar)
    .interactivePopEnabled()
    .errorAlert($error)
    .museFlash($flash, status: state?.status, places: state?.places.count ?? 0)
    .task(id: link.sessionId) { await restoreIfNeeded() }
    .onAppear { controller.viewingSessionId = link.sessionId }
    .onDisappear { if controller.viewingSessionId == link.sessionId { controller.viewingSessionId = nil } }
  }

  // MARK: - Pieces

  /// The city above the answer, and the place count once it has finished.
  /// Progress lives in the header's status line.
  private var caption: String? {
    let count = state.flatMap { $0.status == .completed && !$0.places.isEmpty ? "\($0.places.count) places" : nil }
    let parts = [state?.cityName ?? link.cityName, count].compactMap { $0 }.filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  /// Save and Share, which lived in the navigation bar before the Muse header replaced it.
  @ViewBuilder private func actions(_ state: SearchState) -> some View {
    let canSave = !isLive && state.status == .completed && state.destination == .itinerary
    if canSave || state.hasResult {
      HStack(spacing: 8) {
        if canSave {
          Button(saveStatus ?? "Save", systemImage: "bookmark") { Task { await save(state) } }.disabled(saveStatus != nil)
        }
        if state.hasResult {
          ShareLink(item: ItineraryShareText.text(for: state)) { Label("Share", systemImage: "square.and.arrow.up") }
        }
      }
      .buttonStyle(MusePillButtonStyle())
      .padding(.leading, 4)
    }
  }

  /// Stop while this search streams; the follow-up composer once it has finished.
  @ViewBuilder private var bottomBar: some View {
    if isLive {
      Button("Stop", systemImage: "stop.fill") { controller.stop() }
        .buttonStyle(MusePillButtonStyle())
        .frame(maxWidth: .infinity)
        .padding(LociTheme.defaultPadding)
        .background(Color.museCanvas)
    } else if let state, !state.isActive, state.sessionId != nil {
      // Follow-ups continue this session (web /chat sends sessionId + cityName),
      // so the page keeps showing the live state under the same link.
      SearchComposer(
        placeholder: "Ask a follow-up",
        cityName: state.cityName,
        sessionId: state.sessionId,
        style: .muse,
        onFocusChange: { isComposing = $0 }
      ) { _ in }
        .padding(.horizontal, LociTheme.defaultPadding)
        .padding(.vertical, 10)
        .background(Color.museCanvas)
    }
  }

  private var unavailable: some View {
    ContentUnavailableView {
      Label("Search not found", systemImage: "magnifyingglass")
    } description: {
      Text("This search finished on another device or has expired.")
    }
  }

  // MARK: - Actions

  /// "New chat": leave this page for Ask Loci with the cursor in its composer,
  /// from whichever tab pushed it (Discover, Saved or Ask Loci itself).
  private func newChat() {
    dismiss()
    router.startNewChat()
  }

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

/// One search as a chat turn: the query as the user bubble, then everything
/// the server sent back inside a single agent bubble. Pure rendering of a
/// `SearchState`, so the design preview can show it without a session.
struct SearchTranscript: View {
  let state: SearchState
  var caption: String?
  var onRerun: (String) -> Void = { _ in }

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var hasAgentTurn: Bool { state.status != .idle || !state.text.isEmpty || state.hasResult }
  private var hasItineraryTitle: Bool {
    guard let itinerary = state.itinerary else { return false }
    return state.destination == .itinerary && !itinerary.itineraryResponse.itineraryName.isEmpty
  }
  private var showsSkeleton: Bool { state.isActive && state.places.isEmpty && state.text.isEmpty && !hasItineraryTitle }
  private var arrival: AnyTransition { reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if !state.query.isEmpty {
        MuseBubble(role: .user) { Text(state.query) }
      }
      if let caption {
        Text(caption).lociCoordStyle().padding(.horizontal, 4).padding(.top, 4)
      }
      if hasAgentTurn {
        MuseBubble(role: .agent) { agentContent }.transition(arrival)
      }
    }
    .animation(reduceMotion ? LociTheme.reducedFade : LociTheme.resultArrive, value: hasAgentTurn)
  }

  private var agentContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      if case .failed(let message) = state.status {
        Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Color.lociDestructive)
        if !state.query.isEmpty { rerunButton }
      }

      if hasItineraryTitle, let response = state.itinerary?.itineraryResponse {
        Text(response.itineraryName).font(.lociTitle())
        if !response.overallDescription.isEmpty { Text(response.overallDescription) }
      } else if !state.text.isEmpty, state.places.isEmpty {
        // Tokens as they arrive, until a structured result replaces them. The caret sits in the bubble.
        Text(state.status == .streaming ? state.text + " ▍" : state.text)
          .animation(reduceMotion ? nil : LociTheme.reducedFade, value: state.text)
      } else if showsSkeleton {
        SkeletonCards()
      }

      if !state.places.isEmpty {
        LazyVStack(spacing: 12) {
          ForEach(state.places, id: \.stableID) { poi in
            POICardView(poi: poi).transition(arrival)
          }
        }
        .animation(reduceMotion ? LociTheme.reducedFade : LociTheme.resultArrive, value: state.places.count)
      }

      if state.status == .completed, state.places.isEmpty, state.destination != .itinerary {
        Text("The list finished on the server but didn't reach this phone.").foregroundStyle(Color.museTextSecondary)
        rerunButton
      }
    }
    .frame(maxWidth: state.places.isEmpty && !showsSkeleton ? nil : .infinity, alignment: .leading)
  }

  private var rerunButton: some View {
    Button("Run the search again") { onRerun(state.query) }.buttonStyle(.borderedProminent).tint(.lociForest)
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
