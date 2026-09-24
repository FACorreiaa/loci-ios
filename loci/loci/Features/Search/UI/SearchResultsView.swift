import LociConnectProto
import StoreKit
import SwiftUI

/// The result page for one search session: web's `/itinerary`, `/hotels`,
/// `/restaurants` and `/activities` with `?sessionId=&cityName=&domain=`.
///
/// While the search runs it shows skeleton cards, then the places as the
/// structured events land; tokens are never rendered (web does the same). Opened later (a notification tap, a deep link)
/// it restores the session the way web's `restoreOrHydrateSession` does:
/// the live search, then this phone's copy, then GetChatSession, then a re-run.
///
/// Drawn as a Muse chat (apps/_reviews/muse-chat-contract.md): the query is the
/// user bubble, the answer and its places are the agent bubble.
struct SearchResultsView: View {
  let link: SessionLink
  /// The prompt a Recents row carried. When the session cannot be restored,
  /// "Run it again" starts it afresh (web re-runs from `?message=`).
  var rerunMessage: String?

  @Environment(\.dismiss) private var dismiss
  @Environment(\.requestReview) private var requestReview
  private let controller = SearchSessionController.shared
  private let reviews = ReviewPrompter.shared
  private let router = AppRouter.shared
  @State private var restored: SearchState?
  @State private var isRestoring = false
  @State private var saveStatus: String?
  @State private var error: String?
  @State private var isComposing = false
  @State private var flash: MuseActivity.Flash?
  /// Proactive messages and the standing-task card, after the search turn.
  @State private var thread = MuseThread()
  @State private var scroll = ScrollPosition()
  /// A message a chat push named, to bring into view once it is on the page.
  @State private var revealMessageId: String?
  /// A re-run started from this page and not yet named by the server.
  @State private var awaitingRerun = false
  /// The session a re-run started; the page follows it from then on.
  @State private var followedSessionId: String?

  /// The session this page shows: the link's, or the one a re-run started.
  private var sessionId: String { followedSessionId ?? link.sessionId }

  /// The re-run between Start and the server naming its session.
  private var isRerunPending: Bool { awaitingRerun && controller.state.sessionId == nil && controller.state.status != .idle }

  /// The live search when it is this session, otherwise what was restored.
  private var state: SearchState? {
    controller.state.sessionId == sessionId || isRerunPending ? controller.state : restored
  }

  /// This page is showing the search that is streaming right now.
  private var isLive: Bool {
    guard let state else { return false }
    return state.isActive && (controller.state.sessionId == sessionId || isRerunPending)
  }

  var body: some View {
    ScrollView {
      ScrollViewReader { proxy in
        VStack(alignment: .leading, spacing: 12) {
          if let state {
            SearchTranscript(state: state, caption: caption) { query in Task { await rerun(query) } }
            actions(state)
            MuseThreadTail(thread: thread, sessionId: state.sessionId ?? sessionId)
          } else if isRestoring || awaitingRerun {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
          } else {
            unavailable
          }
        }
        .padding(.horizontal, LociTheme.defaultPadding)
        .padding(.vertical, 12)
        .onChange(of: revealMessageId) { _, id in
          guard let id else { return }
          withAnimation(LociTheme.resultArrive) { proxy.scrollTo(id, anchor: .top) }
          revealMessageId = nil
        }
      }
    }
    .scrollPosition($scroll)
    // A card or a confirmation lands under a long answer: bring it into view.
    .onChange(of: thread.card != nil) { _, hasCard in if hasCard { scrollToEnd() } }
    .onChange(of: thread.confirmedWatchId) { _, id in if id != nil { scrollToEnd() } }
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
    .task(id: reviews.isPromptDue) { await askForReviewIfDue() }
    .task(id: sessionId) {
      await restoreIfNeeded()
      guard !sessionId.isEmpty else { return }
      await thread.loadHistory(sessionId: sessionId)
      // Opened from a chat push (cold or warm start): the message is loaded now.
      if let refresh = router.takeThreadRefresh(for: sessionId) { reveal(refresh) }
    }
    // A chat push for this page while it is on screen, or a tap on one that
    // re-selects it: fetch the thread again so the new message appears.
    .onChange(of: router.threadRefresh) { _, refresh in
      guard refresh?.sessionId == sessionId, controller.viewingSessionId == sessionId,
        let refresh = router.takeThreadRefresh(for: sessionId)
      else { return }
      Task {
        await thread.loadHistory(sessionId: sessionId)
        reveal(refresh)
      }
    }
    // A re-run from "Search not found": follow the session the server names.
    .onChange(of: controller.startedLink) { _, started in
      guard awaitingRerun, let started else { return }
      awaitingRerun = false
      followedSessionId = started.sessionId
      controller.viewingSessionId = started.sessionId
    }
    .onAppear { controller.viewingSessionId = sessionId }
    .onDisappear { if controller.viewingSessionId == sessionId { controller.viewingSessionId = nil } }
  }

  /// Ask for a rating once the finished-search flash has settled. Leaving the
  /// page first drops the ask; the count stands, so the next success earns it again.
  private func askForReviewIfDue() async {
    guard reviews.isPromptDue else { return }
    try? await Task.sleep(for: ReviewPrompter.settleDelay)
    guard !Task.isCancelled else {
      reviews.skipPrompt()
      return
    }
    guard reviews.isPromptDue else { return }
    reviews.didPrompt()
    requestReview()
  }

  // MARK: - Pieces

  /// The city above the answer, and the place count once it has finished.
  /// Progress lives in the header's status line.
  private var caption: String? {
    let count = state.flatMap { !$0.isActive && !$0.places.isEmpty ? "\($0.places.count) places" : nil }
    let parts = [state?.cityName ?? link.cityName, count].compactMap { $0 }.filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  /// Save and Share, which lived in the navigation bar before the Muse header replaced it.
  @ViewBuilder private func actions(_ state: SearchState) -> some View {
    let canSave = !isLive && state.hasResult
    if canSave || state.hasResult {
      HStack(spacing: 8) {
        if canSave {
          Button(saveStatus ?? "Save", systemImage: "bookmark") { Task { await save(state) } }.disabled(saveStatus != nil)
        }
        if state.hasResult {
          ShareLink(item: ShareText.build(title: shareTitle(state), groups: state.dayGroups, description: state.cityData?.description_p)) {
            Label("Share", systemImage: "square.and.arrow.up")
          }
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
        onFocusChange: { isComposing = $0 },
        intercept: offerStandingTask
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
    } actions: {
      if let message = rerunMessage, !message.isEmpty {
        Button("Run it again") { Task { await runAgain(message) } }
          .buttonStyle(.borderedProminent)
          .tint(Color.lociForest)
      }
    }
  }

  // MARK: - Actions

  /// "New chat": leave this page for Ask Loci with the cursor in its composer,
  /// from whichever tab pushed it (Discover, Saved or Ask Loci itself).
  private func newChat() {
    dismiss()
    router.startNewChat()
  }

  private func scrollToEnd() {
    withAnimation(LociTheme.resultArrive) { scroll.scrollTo(edge: .bottom) }
  }

  /// Bring the pushed message into view; without an id this thread knows, the
  /// newest message is at the end.
  private func reveal(_ refresh: ThreadRefresh) {
    if let id = refresh.messageId.flatMap(thread.messageId(matching:)) {
      revealMessageId = id
    } else if !thread.messages.isEmpty {
      scrollToEnd()
    }
  }

  /// A follow-up that reads like "every morning, tell me…" becomes a
  /// standing-task card on this thread instead of a new search.
  private func offerStandingTask(_ text: String) -> Bool {
    guard StandingRequest.matches(text) else { return false }
    Task { await thread.offer(text) }
    return true
  }

  private func restoreIfNeeded() async {
    // A Recents row whose prompt kept no session has nothing to restore.
    guard controller.state.sessionId != sessionId, restored == nil, !sessionId.isEmpty else { return }
    isRestoring = true
    restored = await controller.state(for: link)
    isRestoring = false
  }

  private func rerun(_ query: String) async {
    do {
      try await controller.start(query: query, cityName: state?.cityName ?? link.cityName)
    } catch { self.error = error.userMessage }
  }

  /// Start the row's prompt again as a new search; the page follows it once
  /// the server names the session (`startedLink`).
  private func runAgain(_ message: String) async {
    awaitingRerun = true
    do {
      try await controller.start(query: message, cityName: link.cityName)
    } catch {
      awaitingRerun = false
      self.error = error.userMessage
    }
  }

  private func shareTitle(_ state: SearchState) -> String {
    let city = state.cityData?.city ?? state.cityName ?? ""
    let name = state.itinerary?.itineraryResponse.itineraryName ?? ""
    return name.isEmpty ? state.destination.bookmarkTitle(city: city) : name
  }

  /// Web's Save: the phone already keeps its copy when the search finishes;
  /// this adds the account bookmark with the fields /itinerary sends.
  private func save(_ state: SearchState) async {
    let city = state.cityData?.city ?? state.cityName ?? ""
    let description = state.cityData.map { $0.description_p.isEmpty ? "Itinerary for \(city)" : $0.description_p } ?? "Itinerary for \(city)"
    do {
      try await ResultsAPI.bookmark(title: shareTitle(state), description: description, cityName: city, sessionId: state.sessionId)
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

  private var hasAgentTurn: Bool { state.status != .idle || state.hasResult }
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
        MuseBubble(role: .agent) { MultiCityResults(state: state, onRerun: onRerun) }.transition(arrival)
      }
    }
    .animation(reduceMotion ? LociTheme.reducedFade : LociTheme.resultArrive, value: hasAgentTurn)
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
