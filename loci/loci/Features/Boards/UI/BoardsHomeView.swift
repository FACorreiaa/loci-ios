import LociConnectProto
import SwiftUI

/// Community boards (web: /boards): every board's posts in one feed, with the
/// boards to open above it. Entered from Discover and Profile.
struct BoardsHomeView: View {
  static let symbol = "bubble.left.and.text.bubble.right"

  @State private var store: BoardsFeedStore
  @State private var creatingBoard = false

  init(store: BoardsFeedStore = BoardsFeedStore()) { _store = State(initialValue: store) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        directory
        BoardsFeedSection(store: store, emptyText: "Nothing posted yet. Open a board and start the first thread.")
      }.padding(LociTheme.defaultPadding)
    }.background(Color.lociPaper.ignoresSafeArea()).navigationTitle("Boards").navigationBarTitleDisplayMode(.inline).toolbar {
      if store.isAdmin {
        ToolbarItem(placement: .topBarTrailing) {
          NavigationLink(value: AppRoute.sanctions(RouteRef(store))) {
            Label("Moderation", systemImage: "checkmark.shield").labelStyle(.iconOnly)
          }
        }
      }
      if store.canWrite { ToolbarItem(placement: .topBarTrailing) { Button("New board", systemImage: "plus") { creatingBoard = true } } }
    }.sheet(isPresented: $creatingBoard) { CreateBoardSheet(service: store.service) { _ in Task { await store.load() } } }.refreshable {
      await store.load()
    }.task { if store.phase == .idle { await store.load() } }.errorAlert($store.error).onAppear { Analytics.screen("boards") }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Community").lociCoordStyle(10)
      Text("Boards").font(.lociDisplay(28)).foregroundStyle(Color.lociInk)
      Text("Trip reports, itineraries worth stealing, and places people actually went.").font(.lociBody(15)).foregroundStyle(Color.lociMutedInk)
    }
  }

  @ViewBuilder private var directory: some View {
    if !store.boards.isEmpty {
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(store.boards, id: \.id) { board in
            NavigationLink(value: AppRoute.board(slug: board.slug, from: RouteRef(store))) {
              VStack(alignment: .leading, spacing: 2) {
                Text(board.name).font(.lociHeadline(15)).foregroundStyle(Color.lociInk)
                Text("^[\(Int(board.postCount)) post](inflect: true)").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
              }.lociCard(padding: 12)
            }.buttonStyle(.plain)
          }
        }
      }.scrollIndicators(.hidden)
    }
  }
}

/// One board (web: /boards/:slug).
struct BoardView: View {
  @State private var store: BoardsFeedStore
  @State private var composing = false
  @State private var confirmDelete = false
  @Environment(\.dismiss) private var dismiss

  init(store: BoardsFeedStore) { _store = State(initialValue: store) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        BoardsFeedSection(store: store, emptyText: "No posts here yet. Be the first.")
      }.padding(LociTheme.defaultPadding)
    }.background(Color.lociPaper.ignoresSafeArea()).navigationTitle(store.board?.name ?? store.slug).navigationBarTitleDisplayMode(.inline).toolbar {
      if store.isAdmin {
        ToolbarItem(placement: .topBarTrailing) { Button("Delete board", systemImage: "trash", role: .destructive) { confirmDelete = true } }
      }
      if store.canWrite { ToolbarItem(placement: .topBarTrailing) { Button("Post", systemImage: "square.and.pencil") { composing = true } } }
    }.confirmationDialog("Delete this board and every post in it?", isPresented: $confirmDelete, titleVisibility: .visible) {
      Button("Delete board", role: .destructive) { Task { if await store.deleteBoard() { dismiss() } } }
    }.sheet(isPresented: $composing) {
      ComposePostSheet(boardSlug: store.slug, boardName: store.board?.name ?? store.slug, service: store.service) { _ in
        Task { await store.reload(sort: .new) }
      }
    }.refreshable { await store.load() }.task { if store.phase == .idle { await store.load() } }.errorAlert($store.error).onAppear {
      Analytics.screen("board")
    }
  }

  @ViewBuilder private var header: some View {
    if let board = store.board {
      VStack(alignment: .leading, spacing: 6) {
        Text("/boards/\(board.slug)").lociCoordStyle(10)
        Text(board.name).font(.lociDisplay(26)).foregroundStyle(Color.lociInk)
        if !board.description_p.isEmpty { Text(board.description_p).font(.lociBody(15)).foregroundStyle(Color.lociMutedInk) }
      }
    }
  }
}
