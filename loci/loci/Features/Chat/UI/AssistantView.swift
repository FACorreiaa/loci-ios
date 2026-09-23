import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Ask Loci (web: /chat). Past sessions from ChatService.GetChatSessions, a
/// composer that starts a streaming search, and the landing point for deep
/// links and notification taps (`AppRouter.pendingSession`).
struct AssistantView: View {
  private let router = AppRouter.shared
  private let controller = SearchSessionController.shared
  @State private var path: [SessionLink] = []
  @State private var sessions: [Loci_Chat_ChatSession] = []
  @State private var error: String?
  @State private var composerFocus = 0

  var body: some View {
    NavigationStack(path: $path) {
      ScrollViewReader { proxy in
        List {
          if let live = controller.state.link, controller.state.isActive {
            Section("Running now") {
              NavigationLink(value: live) {
                Label(controller.state.query, systemImage: "sparkles").lineLimit(2)
              }
              .id(Self.topRow)
            }
            .listRowBackground(Color.museAgentBubble)
          }
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
          if sessions.isEmpty, !controller.state.isActive {
            ContentUnavailableView("Ask Loci anything", systemImage: "bubble.left.and.bubble.right", description: Text("Where to, and for how long?"))
          }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
          MuseChatHeader(
            onLeading: { scrollToTop(proxy) },
            onNewChat: { composerFocus += 1 }
          )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          SearchComposer(style: .muse, focusRequest: composerFocus) { path.append($0) }
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

struct SessionRow: View {
  let session: Loci_Chat_ChatSession

  private var title: String {
    let firstUser = session.conversationHistory.first { $0.role == .user }?.content
    return firstUser ?? (session.cityName.isEmpty ? "Conversation" : session.cityName)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).lineLimit(2).foregroundStyle(Color.lociInk)
      HStack {
        if !session.cityName.isEmpty { Text(session.cityName) }
        if session.hasUpdatedAt { Text(session.updatedAt.date, style: .relative) }
      }
      .lociCoordStyle(10)
    }
  }
}
