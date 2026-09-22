import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Ask Loci (web: /chat). Past sessions from ChatService.GetChatSessions, a
/// composer that starts a streaming search, and the landing point for deep
/// links and notification taps (`AppRouter.pendingSession`).
struct AssistantView: View {
  @State private var router = AppRouter.shared
  @State private var controller = SearchSessionController.shared
  @State private var path: [SessionLink] = []
  @State private var sessions: [Loci_Chat_ChatSession] = []
  @State private var error: String?

  var body: some View {
    NavigationStack(path: $path) {
      List {
        if let live = controller.state.link, controller.state.isActive {
          Section("Running now") {
            NavigationLink(value: live) {
              Label(controller.state.query, systemImage: "sparkles").lineLimit(2)
            }
          }
        }
        Section("Recent") {
          ForEach(sessions, id: \.id) { session in
            NavigationLink(value: Self.link(for: session)) { SessionRow(session: session) }
          }
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .background(Color.lociPaper.ignoresSafeArea())
      .overlay {
        if sessions.isEmpty, !controller.state.isActive {
          ContentUnavailableView("Ask Loci anything", systemImage: "bubble.left.and.bubble.right", description: Text("Where to, and for how long?"))
        }
      }
      .safeAreaInset(edge: .bottom) {
        SearchComposer { path.append($0) }.padding(LociTheme.defaultPadding).background(.bar)
      }
      .navigationTitle("Ask Loci")
      .navigationDestination(for: SessionLink.self) { SearchResultsView(link: $0) }
      .refreshable { await load() }
      .task { await load() }
      .onAppear(perform: openPending)
      .onChange(of: router.pendingSession) { openPending() }
      .errorAlert($error)
    }
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
