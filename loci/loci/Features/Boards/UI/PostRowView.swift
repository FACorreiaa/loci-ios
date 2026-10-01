import LociConnectProto
import SwiftUI

/// Up/down arrows with the score between them.
struct VoteButtons: View {
  let score: Int32
  let myVote: Int32
  let onVote: (Int32) -> Void

  var body: some View {
    VStack(spacing: 2) {
      arrow(1, symbol: "arrowshape.up")
      Text("\(score)").font(.lociCoord(12)).monospacedDigit().foregroundStyle(myVote != 0 ? Color.lociForest : Color.lociMutedInk)
      arrow(-1, symbol: "arrowshape.down")
    }.frame(width: 36).accessibilityElement(children: .contain)
  }

  private func arrow(_ value: Int32, symbol: String) -> some View {
    Button {
      onVote(value)
    } label: {
      Image(systemName: myVote == value ? "\(symbol).fill" : symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(
        myVote == value ? Color.lociForest : Color.lociMutedInk
      ).frame(width: 32, height: 28).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityLabel(value == 1 ? "Upvote" : "Downvote").accessibilityAddTraits(myVote == value ? .isSelected : [])
  }
}

/// Who wrote it and when, with the board chip in a cross-board feed.
struct PostByline: View {
  let post: Loci_Boards_V1_Post
  var showBoard = false

  var body: some View {
    HStack(spacing: 6) {
      if showBoard, post.hasBoard {
        Text(post.board.name).font(.lociCaption(11)).padding(.horizontal, 6).padding(.vertical, 2).overlay(Capsule().stroke(Color.lociBorder))
      }
      if post.hasAuthor {
        UserAvatar(user: post.author, size: 18)
        Text(post.author.shownName)
      }
      Text(BoardsModel.age(post.createdAt))
      Label("\(post.commentCount)", systemImage: "bubble.left").labelStyle(.titleAndIcon).accessibilityLabel("\(post.commentCount) comments")
    }.font(.lociCaption()).foregroundStyle(Color.lociMutedInk).lineLimit(1)
  }
}

/// One line of a feed: arrows, then title, domain and byline opening the post.
/// The arrows sit outside the link so a vote never opens the post.
struct PostRowView<Destination: View>: View {
  let post: Loci_Boards_V1_Post
  var showBoard = false
  let onVote: (Int32) -> Void
  @ViewBuilder let destination: () -> Destination

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      VoteButtons(score: post.score, myVote: post.myVote, onVote: onVote)
      NavigationLink(destination: destination) {
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(post.title).font(.lociHeadline(16)).foregroundStyle(Color.lociInk).multilineTextAlignment(.leading)
            if post.hasAttachment {
              Image(systemName: "paperclip").font(.caption).foregroundStyle(Color.lociMutedInk).accessibilityLabel("Has a Loci item attached")
            }
          }
          if !post.domain.isEmpty { Text(post.domain).font(.lociCaption()).foregroundStyle(Color.lociMutedInk) }
          PostByline(post: post, showBoard: showBoard)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.plain)
    }.padding(.vertical, 10)
  }
}
