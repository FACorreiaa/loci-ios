import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Ask Loci (web: /chat). Past sessions from ChatService.GetChatSessions, a
/// composer that starts a streaming search, and the landing point for deep
/// links and notification taps (`AppRouter.pendingSession`).
///
/// The live search (`controller.state`) changes on every streamed token, so
/// only the small pieces that show it read it: the header, the "Running now"
/// row, the empty state and the flash tracker. This body never does.
struct AssistantView: View {
  private let router = AppRouter.shared
  private let controller = SearchSessionController.shared
  @State private var path: [SessionLink] = []
  @State private var sessions: [Loci_Chat_ChatSession] = []
  @State private var error: String?
  @State private var composerFocus = 0
  @State private var isComposing = false
  @State private var flash: MuseActivity.Flash?

  var body: some View {
    NavigationStack(path: $path) {
      ScrollViewReader { proxy in
        List {
          RunningNowSection(rowID: Self.topRow)
          Section("Recent") {
            ForEach(sessions, id: \.id) { session in
              NavigationLink(value: Self.link(for: session)) { SessionRow(session: session) }
            }
          }
          .listRowBackground(Color.museAgentBubble)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.museCanvas.ignoresSafeArea())
        .overlay {
          if sessions.isEmpty { IdleEmptyState() }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
          LiveMuseChatHeader(
            flash: flash,
            isListening: isComposing,
            onLeading: { scrollToTop(proxy) },
            onNewChat: { composerFocus += 1 }
          )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          SearchComposer(style: .muse, focusRequest: composerFocus, onFocusChange: { isComposing = $0 }) { path.append($0) }
            .padding(.horizontal, LociTheme.defaultPadding)
            .padding(.vertical, 10)
            .background(Color.museCanvas)
        }
      }
      .navigationTitle("Ask Loci")
      .toolbarVisibility(.hidden, for: .navigationBar)
      .navigationDestination(for: SessionLink.self) { SearchResultsView(link: $0) }
      .refreshable { await load() }
      .task { await load() }
      .onAppear(perform: openPending)
      .onChange(of: router.pendingSession) { openPending() }
      .onChange(of: router.newChatRequest) { Task { await startNewChat() } }
      .modifier(LiveMuseFlash(flash: $flash))
      .errorAlert($error)
    }
  }

  private static let topRow = "running-now"

  /// The header's left button: back to the top of the conversation list.
  private func scrollToTop(_ proxy: ScrollViewProxy) {
    let target: String? = controller.state.isActive && controller.state.link != nil ? Self.topRow : sessions.first?.id
    guard let target else { return }
    withAnimation(LociTheme.selectionSettle) { proxy.scrollTo(target, anchor: .top) }
  }

  /// "New chat" from a results page: back to this root, then the cursor in the
  /// composer once the pop has finished (focus set mid-transition is dropped).
  private func startNewChat() async {
    let wasPushed = !path.isEmpty
    path = []
    if wasPushed { try? await Task.sleep(for: .milliseconds(450)) }
    composerFocus += 1
  }

  private func openPending() {
    guard let link = router.pendingSession else { return }
    router.pendingSession = nil
    path = [link]
  }

  private func load() async {
    var request = Loci_Chat_GetChatSessionsRequest()
    request.pagination.page = 1
    request.pagination.pageSize = 25
    do {
      sessions = try await rpc("Could not load your conversations.", request) {
        await Loci_Chat_ChatServiceClient(client: ConnectTransport.shared.protocolClient).getChatSessions(request: $0, headers: [:])
      }.sessions
    } catch { self.error = error.userMessage }
  }

  /// A past session opens as an itinerary page: the only kind the server can restore.
  static func link(for session: Loci_Chat_ChatSession) -> SessionLink {
    SessionLink(destination: .itinerary, sessionId: session.id, cityName: session.cityName.isEmpty ? nil : session.cityName, domain: "itinerary")
  }
}

/// The search running right now, pinned above the history.
private struct RunningNowSection: View {
  let rowID: String
  private let controller = SearchSessionController.shared

  var body: some View {
    if let live = controller.state.link, controller.state.isActive {
      Section("Running now") {
        NavigationLink(value: live) {
          Label(controller.state.query, systemImage: "sparkles").lineLimit(2)
        }
        .id(rowID)
      }
      .listRowBackground(Color.museAgentBubble)
    }
  }
}

/// No history and nothing running.
private struct IdleEmptyState: View {
  private let controller = SearchSessionController.shared

  var body: some View {
    if !controller.state.isActive {
      ContentUnavailableView("Ask Loci anything", systemImage: "bubble.left.and.bubble.right", description: Text("Where to, and for how long?"))
    }
  }
}

/// The Muse header, voiced by the live search.
private struct LiveMuseChatHeader: View {
  let flash: MuseActivity.Flash?
  let isListening: Bool
  let onLeading: () -> Void
  let onNewChat: () -> Void
  private let controller = SearchSessionController.shared

  var body: some View {
    MuseChatHeader(activity: .resolve(controller.state, flash: flash, isListening: isListening), onLeading: onLeading, onNewChat: onNewChat)
  }
}

/// `museFlash` fed from the live search, read here so its changes stop at this modifier.
private struct LiveMuseFlash: ViewModifier {
  @Binding var flash: MuseActivity.Flash?
  private let controller = SearchSessionController.shared

  func body(content: Content) -> some View {
    content.museFlash($flash, status: controller.state.status, places: controller.state.places.count)
  }
}

struct SessionRow: View {
  let session: Loci_Chat_ChatSession

  private var title: String {
    let firstUser = session.conversationHistory.first { $0.role == .user }?.content
    return firstUser ?? (session.cityName.isEmpty ? "Conversation" : session.cityName)
  }

  /// The newest message when the agent posted it on its own: shown under the
  /// title with its caption, so a standing task's news is visible from the list.
  private var proactive: MuseMessage? {
    session.conversationHistory.last.map(MuseMessage.init).flatMap { $0.caption != nil && !$0.text.isEmpty ? $0 : nil }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).lineLimit(2).foregroundStyle(Color.lociInk)
      if let proactive, let caption = proactive.caption {
        VStack(alignment: .leading, spacing: 2) {
          MuseCaption(text: caption).padding(.horizontal, -4)
          Text(MuseMessageView.markdown(proactive.text)).font(.lociBody(15)).foregroundStyle(Color.museText).lineLimit(2)
        }
        .padding(.vertical, 4)
      }
      HStack {
        if !session.cityName.isEmpty { Text(session.cityName) }
        if session.hasUpdatedAt { Text(session.updatedAt.date, style: .relative) }
      }
      .lociCoordStyle(10)
    }
  }
}
