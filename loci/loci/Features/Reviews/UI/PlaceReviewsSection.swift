import LociConnectProto
import SwiftUI

/// The Reviews block in a place's detail: average, count and the star
/// breakdown (GetReviewStatistics), the three latest reviews, "See all", and
/// "Write a review" or "Edit your review". Shown only for a stored POI.
struct PlaceReviewsSection: View {
  @State private var store: PlaceReviewsStore
  @State private var composer: ReviewComposerMode?
  @State private var pendingDelete: LociReview?

  init(store: PlaceReviewsStore) {
    _store = State(initialValue: store)
  }

  init(poiID: String, placeName: String, service: ReviewsService) {
    self.init(store: PlaceReviewsStore(poiID: poiID, placeName: placeName, service: service))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      AdaptiveStack(alignment: .firstTextBaseline) {
        Text("Reviews").lociCoordStyle(10)
        Spacer(minLength: 0)
        if store.phase == .loaded { WriteReviewButton(store: store, composer: $composer) }
      }
      switch store.phase {
      case .idle, .loading:
        ProgressView().frame(maxWidth: .infinity, minHeight: 60).accessibilityLabel("Loading reviews")
      case .failed(let message):
        VStack(alignment: .leading, spacing: 6) {
          Text(message).font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
          Button("Try again") { Task { await store.load() } }.font(.lociCaption(13).weight(.semibold)).tint(Color.lociForest)
        }
      case .loaded:
        loaded
      }
    }
    .reviewActions(store: store, composer: $composer, pendingDelete: $pendingDelete)
    .task(id: store.poiID) { await store.load() }
  }

  @ViewBuilder private var loaded: some View {
    if store.stats.total > 0 || !store.reviews.isEmpty {
      ReviewSummary(stats: store.stats)
      ForEach(store.latest) { review in
        PlaceReviewCard(store: store, review: review, composer: $composer, pendingDelete: $pendingDelete)
      }
      if store.showsSeeAll {
        NavigationLink {
          PlaceReviewsListView(store: store)
        } label: {
          HStack {
            Text("See all \(store.stats.countText)")
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
          }
          .font(.lociBody(15).weight(.semibold))
          .foregroundStyle(Color.lociForest)
          .padding(.vertical, 6)
        }
      }
    } else {
      Text("No reviews yet. Been here? Be the first to say how it was.")
        .font(.lociBody(15)).foregroundStyle(Color.lociMutedInk)
    }
  }
}

/// "Write a review", or "Edit your review" once the caller has one here.
struct WriteReviewButton: View {
  let store: PlaceReviewsStore
  @Binding var composer: ReviewComposerMode?

  var body: some View {
    if let mine = store.mine {
      Button("Edit your review", systemImage: "pencil") { composer = .edit(mine) }
        .font(.lociCaption(14).weight(.semibold)).tint(Color.lociForest)
    } else {
      Button("Write a review", systemImage: "square.and.pencil") { composer = .new }
        .font(.lociCaption(14).weight(.semibold)).tint(Color.lociForest)
    }
  }
}

/// A review card wired to the store: helpful votes, or edit/delete for yours.
struct PlaceReviewCard: View {
  let store: PlaceReviewsStore
  let review: LociReview
  @Binding var composer: ReviewComposerMode?
  @Binding var pendingDelete: LociReview?

  var body: some View {
    let own = store.isOwn(review)
    ReviewCard(
      review: review,
      vote: store.vote(for: review),
      isOwn: own,
      onHelpful: own ? nil : { Task { await store.toggleHelpful(review) } },
      onEdit: own ? { composer = .edit(review) } : nil,
      onDelete: own ? { pendingDelete = review } : nil
    )
  }
}

/// The big average, the stars, the count and a bar per star (5 at the top).
struct ReviewSummary: View {
  let stats: ReviewStats

  var body: some View {
    // The bars get the full width under the average at accessibility sizes.
    AdaptiveStack(alignment: .center, spacing: 16) {
      VStack(spacing: 4) {
        Text(stats.averageText).font(.lociDisplay(40)).foregroundStyle(Color.lociInk).monospacedDigit()
        ReviewStars(rating: stats.average, size: 12)
        Text(stats.countText).font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
      }
      .frame(minWidth: 96)
      .accessibilityElement(children: .combine)
      VStack(spacing: 4) {
        ForEach((1...5).reversed(), id: \.self) { star in
          DistributionBar(stars: star, count: stats.count(stars: star), share: stats.share(stars: star))
        }
      }
    }
    .padding(14)
    .background(Color.lociMuted.opacity(0.6), in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
  }
}

private struct DistributionBar: View {
  let stars: Int
  let count: Int
  let share: Double

  var body: some View {
    HStack(spacing: 6) {
      Text("\(stars)").font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk).monospacedDigit().fixedSize().frame(minWidth: 10)
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.lociBorder.opacity(0.5))
          Capsule().fill(Color.lociCoral).frame(width: max(share > 0 ? 4 : 0, proxy.size.width * share))
        }
      }
      .frame(height: 6)
      Text("\(count)").font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk).monospacedDigit().frame(minWidth: 18, alignment: .trailing)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(stars) stars: \(count)")
  }
}

extension View {
  /// The write/edit sheet, the delete confirmation and the error alert for a
  /// place's reviews. The alert only presents from the screen on top, since
  /// the section and "See all" share one store.
  func reviewActions(store: PlaceReviewsStore, composer: Binding<ReviewComposerMode?>, pendingDelete: Binding<LociReview?>) -> some View {
    modifier(ReviewActions(store: store, composer: composer, pendingDelete: pendingDelete))
  }
}

private struct ReviewActions: ViewModifier {
  @Bindable var store: PlaceReviewsStore
  @Binding var composer: ReviewComposerMode?
  @Binding var pendingDelete: LociReview?
  @State private var isOnTop = false

  func body(content: Content) -> some View {
    content
      .sheet(item: $composer) { mode in
        ReviewComposer(
          mode: mode,
          placeName: store.placeName,
          onSubmit: { form, editing in await store.submit(form, editing: editing) },
          onDelete: { review in await store.delete(review) },
          error: $store.error
        )
      }
      .confirmationDialog(
        "Delete your review?",
        isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
        titleVisibility: .visible,
        presenting: pendingDelete
      ) { review in
        Button("Delete", role: .destructive) { Task { _ = await store.delete(review) } }
      } message: { _ in
        Text("This can't be undone.")
      }
      .errorAlert(Binding(get: { isOnTop && composer == nil ? store.error : nil }, set: { store.error = $0 }))
      .onAppear { isOnTop = true }
      .onDisappear { isOnTop = false }
  }
}
