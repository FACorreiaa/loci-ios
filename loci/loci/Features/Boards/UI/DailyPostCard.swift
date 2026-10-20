import LociConnectProto
import SwiftUI

/// Today's AI-written destination above the all-boards feed, opening the post
/// like a feed row does. A place attachment sits outside the link so it still
/// opens the place; a city one is part of the card.
struct DailyPostCard: View {
  let post: Loci_Boards_V1_Post
  let route: AppRoute

  private var attachmentOpensPlace: Bool { post.hasAttachment && post.attachment.kind == .poi }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      NavigationLink(value: route) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Today's destination").lociCoordStyle(10)
          Text(post.title).font(.lociHeadline(18)).foregroundStyle(Color.lociInk).multilineTextAlignment(.leading)
          if !post.body.isEmpty {
            Text(PostDetailView.bodyText(post.body)).font(.lociBody(15)).foregroundStyle(Color.lociMutedInk).lineLimit(3)
              .multilineTextAlignment(.leading)
          }
          if post.hasAttachment, !attachmentOpensPlace { BoardAttachmentCard(attachment: post.attachment) }
          PostByline(post: post)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityElement(children: .combine).accessibilityLabel(accessibilityText)
      if attachmentOpensPlace { BoardAttachmentCard(attachment: post.attachment) }
    }.lociCard()
  }

  private var accessibilityText: String {
    var parts = ["Today's destination", post.title]
    if post.hasAttachment, !attachmentOpensPlace, !post.attachment.title.isEmpty { parts.append(post.attachment.title) }
    if post.isAiGenerated { parts.append("AI generated post") }
    return parts.joined(separator: ", ")
  }
}

#Preview {
  NavigationStack {
    ScrollView {
      if let post = Loci_Boards_V1_Post.previewFeed.first(where: { $0.board.slug == BoardsAPI.dailyBoardSlug }) {
        DailyPostCard(post: post, route: .boardPost(id: post.id, feed: RouteRef(BoardsFeedStore(service: PreviewBoardsService(), myID: { "u-ana" }))))
          .padding(LociTheme.defaultPadding)
      }
    }.background(Color.lociPaper.ignoresSafeArea()).appRouteDestinations()
  }
}
