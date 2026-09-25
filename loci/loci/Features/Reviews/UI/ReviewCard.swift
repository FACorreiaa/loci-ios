import SwiftUI

/// One review (web: ReviewCard): who, when, the stars, the title, the text
/// folded at 200 characters with "Read more", the visit month, and either a
/// helpful vote or, for your own, Edit / Delete.
struct ReviewCard: View {
  let review: LociReview
  var vote: HelpfulVote?
  var isOwn = false
  /// My reviews: the place name leads, the reviewer (you) is left out.
  var showsPlace = false
  /// False inside a tappable row, where a button would steal the tap.
  var isInteractive = true
  var onHelpful: (() -> Void)?
  var onEdit: (() -> Void)?
  var onDelete: (() -> Void)?

  @State private var expanded = false
  @Environment(\.dynamicTypeSize) private var typeSize

  private var dateLine: String {
    var parts: [String] = []
    if let created = review.createdAt { parts.append(created.formatted(.dateTime.day().month(.abbreviated).year())) }
    if review.isEdited { parts.append("Edited") }
    return parts.joined(separator: " · ")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      if !review.title.isEmpty {
        Text(review.title).font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
      }
      content
      if let visit = review.visitDate {
        Label(ReviewPayload.visitLabel(visit), systemImage: "calendar").font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
      }
      if isInteractive { footer }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.lociCard, in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous).stroke(Color.lociBorder.opacity(0.6)))
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 10) {
      if showsPlace {
        Image(systemName: "mappin.and.ellipse")
          .foregroundStyle(Color.lociForest)
          .frame(width: 36, height: 36)
          .background(Color.lociMuted, in: Circle())
          .accessibilityHidden(true)
      } else {
        ReviewAvatar(review: review)
      }
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 4) {
          Text(showsPlace ? (review.placeName.isEmpty ? "A place" : review.placeName) : review.displayName)
            .font(.lociHeadline(15)).foregroundStyle(Color.lociInk).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
          if review.isVerified, !showsPlace {
            Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(Color.lociForest).accessibilityLabel("Verified reviewer")
          }
        }
        AdaptiveStack(spacing: 6) {
          ReviewStars(rating: Double(review.rating), size: 11)
          if !dateLine.isEmpty { Text(dateLine).font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk).lineLimit(1).minimumScaleFactor(0.8) }
        }
      }
      // The stars already carry the rating; at accessibility sizes the badge's width goes to the name.
      if !typeSize.isAccessibilitySize {
        Spacer(minLength: 4)
        RatingBadge(rating: review.rating)
      }
    }
  }

  @ViewBuilder private var content: some View {
    let folds = ReviewText.needsFold(review.content)
    VStack(alignment: .leading, spacing: 4) {
      Text(expanded || !folds ? review.content : ReviewText.folded(review.content))
        .font(.lociBody(15)).foregroundStyle(Color.lociInk)
        .fixedSize(horizontal: false, vertical: true)
      if folds, isInteractive {
        Button(expanded ? "Show less" : "Read more") { withAnimation(.smooth) { expanded.toggle() } }
          .font(.lociCaption(13).weight(.semibold))
          .foregroundStyle(Color.lociForest)
          .buttonStyle(.plain)
      }
    }
  }

  @ViewBuilder private var footer: some View {
    if isOwn {
      HStack {
        Label("Your review", systemImage: "person.crop.circle").font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
        Spacer()
        if onEdit != nil || onDelete != nil {
          Menu {
            if let onEdit { Button("Edit", systemImage: "pencil", action: onEdit) }
            if let onDelete { Button("Delete", systemImage: "trash", role: .destructive, action: onDelete) }
          } label: {
            Image(systemName: "ellipsis").frame(width: 32, height: 28).contentShape(Rectangle())
          }
          .foregroundStyle(Color.lociMutedInk)
          .accessibilityLabel("Review actions")
        }
      }
    } else if let vote, let onHelpful {
      Button(action: onHelpful) {
        Label(vote.count >= 1 ? "Helpful · \(vote.count)" : "Helpful", systemImage: vote.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
          .font(.lociCaption(13))
          .padding(.horizontal, 10).padding(.vertical, 5)
          .background(vote.isLiked ? Color.lociSage : Color.lociMuted, in: Capsule())
          .foregroundStyle(vote.isLiked ? Color.lociForest : Color.lociInk)
          .contentTransition(.numericText())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(vote.isLiked ? "Marked helpful, \(vote.count) votes" : "Mark helpful, \(vote.count) votes")
      .accessibilityAddTraits(vote.isLiked ? .isSelected : [])
    } else if review.helpfulCount >= 1 {
      Label("\(review.helpfulCount) found this helpful", systemImage: "hand.thumbsup").font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
    }
  }
}

/// The reviewer's picture, or their initial.
struct ReviewAvatar: View {
  let review: LociReview

  var body: some View {
    Group {
      if let url = review.reviewerAvatar {
        AsyncImage(url: url) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          initial
        }
      } else {
        initial
      }
    }
    .frame(width: 36, height: 36)
    .clipShape(Circle())
    .accessibilityHidden(true)
  }

  private var initial: some View {
    Text(review.initial).font(.lociHeadline(15)).foregroundStyle(Color.lociPaper)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color.lociForest)
  }
}

/// Five stars, filled to the (rounded-to-half) rating.
struct ReviewStars: View {
  let rating: Double
  var size: CGFloat = 12

  var body: some View {
    HStack(spacing: 1) {
      ForEach(1...5, id: \.self) { star in
        Image(systemName: symbol(star)).font(.system(size: size, weight: .semibold))
      }
    }
    .foregroundStyle(Color.lociCoral)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(rating.formatted(.number.precision(.fractionLength(0...1)))) out of 5 stars")
  }

  private func symbol(_ star: Int) -> String {
    let rounded = (rating * 2).rounded() / 2
    if rounded >= Double(star) { return "star.fill" }
    if rounded + 0.5 >= Double(star) { return "star.leadinghalf.filled" }
    return "star"
  }
}

/// The number in web's colour bands: ≥ 4 green, ≥ 3 amber, else red.
struct RatingBadge: View {
  let rating: Int

  var body: some View {
    let tone = ReviewRating.tone(Double(rating))
    Label("\(rating)", systemImage: "star.fill")
      .font(.lociCaption(12).weight(.semibold))
      .padding(.horizontal, 7).padding(.vertical, 3)
      .foregroundStyle(tone.foreground)
      .background(tone.foreground.opacity(0.14), in: Capsule())
      .accessibilityLabel("\(rating) stars, \(ReviewRating.label(rating))")
  }
}

extension ReviewRating.Tone {
  var foreground: Color {
    switch self {
    case .high: .lociForest
    case .middle: .lociCoral
    case .low: .lociDestructive
    }
  }
}
