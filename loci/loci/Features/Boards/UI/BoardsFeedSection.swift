import LociConnectProto
import SwiftUI

/// Who an admin is about to mute or ban.
struct SanctionTarget: Identifiable {
  let user: Loci_Social_PublicUser
  let kind: Loci_Boards_V1_SanctionKind
  var id: String { user.id + "\(kind.rawValue)" }
}

/// New/Top (and Top's window) above a list of posts. Long-press a post for
/// delete and, for admins, mute or ban its author.
struct BoardsFeedSection: View {
  @Bindable var store: BoardsFeedStore
  let emptyText: String
  @State private var pendingDelete: Loci_Boards_V1_Post?
  @State private var sanctionTarget: SanctionTarget?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("Sort", selection: Binding(get: { store.sort }, set: { value in Task { await store.reload(sort: value) } })) {
        Text("New").tag(Loci_Boards_V1_PostSort.new)
        Text("Top").tag(Loci_Boards_V1_PostSort.top)
      }.pickerStyle(.segmented)

      if store.sort == .top {
        Picker("Window", selection: Binding(get: { store.window }, set: { value in Task { await store.reload(window: value) } })) {
          Text("Today").tag(Loci_Boards_V1_TopWindow.day)
          Text("This week").tag(Loci_Boards_V1_TopWindow.week)
          Text("All time").tag(Loci_Boards_V1_TopWindow.all)
        }.pickerStyle(.segmented)
      }

      if let sanction = store.sanction {
        Label(sanction.viewerExplanation, systemImage: "speaker.slash").font(.lociCaption(13)).foregroundStyle(Color.lociDestructive).padding(12)
          .frame(maxWidth: .infinity, alignment: .leading).background(
            Color.lociDestructive.opacity(0.1),
            in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius)
          )
      }

      content
    }.confirmationDialog(
      "Delete this post?",
      isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
      titleVisibility: .visible
    ) { Button("Delete", role: .destructive) { if let post = pendingDelete { Task { await store.delete(post) } } } }.sheet(item: $sanctionTarget) {
      target in SanctionSheet(target: target, service: store.service) { Task { await store.load() } }
    }
  }

  @ViewBuilder private var content: some View {
    switch store.phase {
    case .idle, .loading: ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
    case .failed(let message): ContentUnavailableView("Couldn't load posts", systemImage: "exclamationmark.bubble", description: Text(message))
    case .loaded:
      if store.posts.isEmpty {
        Text(emptyText).font(.lociBody(15)).foregroundStyle(Color.lociMutedInk).frame(maxWidth: .infinity).padding(.vertical, 40)
      } else {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(store.posts, id: \.id) { post in
            PostRowView(post: post, showBoard: store.slug.isEmpty, route: .boardPost(id: post.id, feed: RouteRef(store))) { value in
              Task { await store.vote(post, pressed: value) }
            }.contextMenu { menu(for: post) }
            Divider()
          }
          if !store.nextCursor.isEmpty {
            Button(store.loadingMore ? "Loading…" : "Load more") { Task { await store.loadMore() } }.buttonStyle(.bordered).tint(.lociForest).frame(
              maxWidth: .infinity
            ).padding(.top, 12).disabled(store.loadingMore)
          }
        }.lociCard(padding: 12)
      }
    }
  }

  @ViewBuilder private func menu(for post: Loci_Boards_V1_Post) -> some View {
    let mine = post.hasAuthor && store.isMine(post.author)
    if mine || store.isAdmin { Button("Delete post", systemImage: "trash", role: .destructive) { pendingDelete = post } }
    if store.isAdmin, !mine, post.hasAuthor {
      Button("Mute author", systemImage: "speaker.slash") { sanctionTarget = SanctionTarget(user: post.author, kind: .mute) }
      Button("Ban author", systemImage: "nosign", role: .destructive) { sanctionTarget = SanctionTarget(user: post.author, kind: .ban) }
    }
  }
}
