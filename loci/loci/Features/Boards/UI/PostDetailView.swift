import LociConnectProto
import SwiftUI

/// A post and its threaded comments (web: /boards/:slug/:postId).
struct PostDetailView: View {
  /// Past this depth replies stop indenting, so deep threads stay readable.
  static let maxIndent = 4

  @State var store: BoardPostStore
  @State private var draft = ""
  @State private var replyingTo: Loci_Boards_V1_Comment?
  @State private var pendingDeleteComment: Loci_Boards_V1_Comment?
  @State private var confirmDeletePost = false
  @State private var sanctionTarget: SanctionTarget?
  @State private var sending = false
  @FocusState private var composerFocused: Bool
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL

  private var feed: BoardsFeedStore { store.feed }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if let post = store.post {
          postCard(post)
          comments(post)
        } else if let failed = store.failed {
          ContentUnavailableView("This post isn't here", systemImage: "bubble.left.and.exclamationmark.bubble.right", description: Text(failed))
        } else {
          ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
        }
      }.padding(LociTheme.defaultPadding)
    }.background(Color.lociPaper.ignoresSafeArea()).navigationTitle(store.post?.board.name ?? "Post").navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom) { composer }.toolbar {
        if let post = store.post {
          ToolbarItem(placement: .topBarTrailing) {
            Menu {
              if !post.url.isEmpty, let url = URL(string: post.url) { ShareLink(item: url) }
              postMenu(post)
            } label: {
              Image(systemName: "ellipsis.circle")
            }.accessibilityLabel("Post actions")
          }
        }
      }.confirmationDialog("Delete this post?", isPresented: $confirmDeletePost, titleVisibility: .visible) {
        Button("Delete", role: .destructive) { Task { if await store.deletePost() { dismiss() } } }
      }.confirmationDialog(
        "Delete this comment?",
        isPresented: Binding(get: { pendingDeleteComment != nil }, set: { if !$0 { pendingDeleteComment = nil } }),
        titleVisibility: .visible
      ) { Button("Delete", role: .destructive) { if let comment = pendingDeleteComment { Task { await store.deleteComment(comment) } } } }.sheet(
        item: $sanctionTarget
      ) { target in SanctionSheet(target: target, service: feed.service) { Task { await store.load() } } }.refreshable { await store.load() }.task {
        if store.post == nil { await store.load() }
      }.errorAlert($store.error).onAppear { Analytics.screen("board_post") }
  }

  private func postCard(_ post: Loci_Boards_V1_Post) -> some View {
    HStack(alignment: .top, spacing: 10) {
      VoteButtons(score: post.score, myVote: post.myVote) { value in Task { await store.vote(pressed: value) } }
      VStack(alignment: .leading, spacing: 10) {
        Text(post.title).font(.lociTitle(22)).foregroundStyle(Color.lociInk)
        PostByline(post: post)
        if !post.url.isEmpty, let url = URL(string: post.url) {
          Button {
            openURL(url)
          } label: {
            Label(post.domain.isEmpty ? post.url : post.domain, systemImage: "arrow.up.right.square").font(.lociCaption(14))
          }.tint(.lociForest)
        }
        if !post.body.isEmpty { Text(LocalizedStringKey(post.body)).font(.lociBody(15)).foregroundStyle(Color.lociInk).textSelection(.enabled) }
        if post.hasAttachment { BoardAttachmentCard(attachment: post.attachment) }
      }
    }.lociCard()
  }

  private func comments(_ post: Loci_Boards_V1_Post) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("\(post.commentCount) \(post.commentCount == 1 ? "comment" : "comments")").font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
      if let sanction = feed.sanction { Text(sanction.viewerExplanation).font(.lociCaption(13)).foregroundStyle(Color.lociDestructive) }
      ForEach(store.rows, id: \.comment.id) { row in
        commentRow(row.comment).padding(.leading, CGFloat(min(row.depth, Self.maxIndent)) * 14).overlay(alignment: .leading) {
          if row.depth > 0 { Rectangle().fill(Color.lociBorder).frame(width: 2).padding(.leading, CGFloat(min(row.depth, Self.maxIndent)) * 14 - 8) }
        }
      }
    }
  }

  private func commentRow(_ comment: Loci_Boards_V1_Comment) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        if comment.deleted || !comment.hasAuthor {
          Text("[deleted]")
        } else {
          UserAvatar(user: comment.author, size: 18)
          Text(comment.author.shownName).foregroundStyle(Color.lociInk)
        }
        Text(BoardsModel.age(comment.createdAt))
      }.font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      if !comment.deleted {
        Text(comment.body).font(.lociBody(15)).foregroundStyle(Color.lociInk).textSelection(.enabled)
        if feed.canWrite {
          Button("Reply") {
            replyingTo = comment
            composerFocused = true
          }.font(.lociCaption(13)).tint(.lociMutedInk)
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).contextMenu {
      if !comment.deleted, comment.hasAuthor {
        let mine = feed.isMine(comment.author)
        if mine || feed.isAdmin { Button("Delete comment", systemImage: "trash", role: .destructive) { pendingDeleteComment = comment } }
        if feed.isAdmin, !mine {
          Button("Mute author", systemImage: "speaker.slash") { sanctionTarget = SanctionTarget(user: comment.author, kind: .mute) }
          Button("Ban author", systemImage: "nosign", role: .destructive) { sanctionTarget = SanctionTarget(user: comment.author, kind: .ban) }
        }
      }
    }
  }

  @ViewBuilder private func postMenu(_ post: Loci_Boards_V1_Post) -> some View {
    let mine = post.hasAuthor && feed.isMine(post.author)
    if mine || feed.isAdmin { Button("Delete post", systemImage: "trash", role: .destructive) { confirmDeletePost = true } }
    if feed.isAdmin, !mine, post.hasAuthor {
      Button("Mute author", systemImage: "speaker.slash") { sanctionTarget = SanctionTarget(user: post.author, kind: .mute) }
      Button("Ban author", systemImage: "nosign", role: .destructive) { sanctionTarget = SanctionTarget(user: post.author, kind: .ban) }
    }
  }

  @ViewBuilder private var composer: some View {
    if store.post != nil, feed.canWrite {
      VStack(alignment: .leading, spacing: 6) {
        if let parent = replyingTo {
          HStack {
            Text("Replying to \(parent.hasAuthor ? parent.author.displayName : "a comment")").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
            Spacer()
            Button("Cancel") { replyingTo = nil }.font(.lociCaption())
          }
        }
        HStack(alignment: .bottom, spacing: 8) {
          TextField(replyingTo == nil ? "Add a comment" : "Write a reply", text: $draft, axis: .vertical).lineLimit(1...5).textFieldStyle(
            .roundedBorder
          ).focused($composerFocused).onChange(of: draft) { _, value in if value.count > 5000 { draft = String(value.prefix(5000)) } }
          Button {
            Task {
              sending = true
              defer { sending = false }
              if await store.comment(draft, parentID: replyingTo?.id) {
                draft = ""
                replyingTo = nil
                composerFocused = false
              }
            }
          } label: {
            Image(systemName: "arrow.up.circle.fill").font(.title2)
          }.tint(.lociForest).disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel(
            replyingTo == nil ? "Send comment" : "Send reply"
          )
        }
      }.padding(.horizontal, LociTheme.defaultPadding).padding(.vertical, 10).background(.bar)
    }
  }
}

/// A Loci item attached to a post, as it was when it was posted. A place opens
/// its detail screen; an itinerary is the poster's own and only shows here.
struct BoardAttachmentCard: View {
  let attachment: Loci_Boards_V1_Attachment

  var body: some View {
    if attachment.kind == .poi {
      NavigationLink {
        SavedPlaceDetailView(item: placeItem)
      } label: {
        card
      }.buttonStyle(.plain)
    } else {
      card
    }
  }

  /// The place as a favourite snapshot: the saved-place screen opens on it at
  /// once and fills in from the server, the same as from Saved.
  private var placeItem: Loci_Favorites_V1_FavoriteItem {
    var item = Loci_Favorites_V1_FavoriteItem()
    item.itemID = attachment.ref
    item.itemName = attachment.title
    item.cityName = attachment.city
    item.category = attachment.subtitle
    item.contentType = .poi
    return item
  }

  private var label: (String, String) {
    switch attachment.kind {
    case .itinerary: ("Itinerary", "point.topleft.down.to.point.bottomright.curvepath")
    case .poi: ("Place", "mappin.and.ellipse")
    case .city: ("City", "building.2")
    default: ("Loci", "sparkles")
    }
  }

  private var card: some View {
    HStack(spacing: 12) {
      Group {
        if let url = URL(string: attachment.imageURL), !attachment.imageURL.isEmpty {
          AsyncImage(url: url) {
            $0.resizable().scaledToFill()
          } placeholder: {
            Color.lociMuted
          }
        } else {
          Image(systemName: label.1).font(.title2).foregroundStyle(Color.lociForest).frame(maxWidth: .infinity, maxHeight: .infinity).background(
            Color.lociForest.opacity(0.1)
          )
        }
      }.frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
      VStack(alignment: .leading, spacing: 2) {
        Text(attachment.city.isEmpty || attachment.kind == .city ? label.0 : "\(label.0) · \(attachment.city)").lociCoordStyle(10)
        Text(attachment.title).font(.lociHeadline(15)).foregroundStyle(Color.lociInk).lineLimit(1)
        if !attachment.subtitle.isEmpty { Text(attachment.subtitle).font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk).lineLimit(2) }
      }
      Spacer(minLength: 0)
    }.lociCard(padding: 10)
  }
}
