import LociConnectProto
import SwiftUI

/// Profile › My reviews (GetUserReviews for the caller). Tap a review for its
/// place; swipe to edit or delete.
struct MyReviewsView: View {
  @State private var store: MyReviewsStore
  @State private var editing: LociReview?
  @State private var pendingDelete: LociReview?

  init(store: MyReviewsStore = MyReviewsStore()) {
    _store = State(initialValue: store)
  }

  var body: some View {
    List {
      if store.phase == .loaded, !store.summary.isEmpty {
        Text(store.summary).lociCoordStyle(10)
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
      }
      ForEach(store.reviews) { review in
        NavigationLink(value: review) {
          ReviewCard(review: review, isOwn: true, showsPlace: true, isInteractive: false)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
          Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = review }
          Button("Edit", systemImage: "pencil") { editing = review }.tint(Color.lociForest)
        }
        .contextMenu {
          Button("Edit", systemImage: "pencil") { editing = review }
          Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = review }
        }
      }
      if store.hasMore {
        HStack {
          Spacer()
          if store.isLoadingMore {
            ProgressView()
          } else {
            Button("Load more") { Task { await store.loadMore() } }.tint(Color.lociForest)
          }
          Spacer()
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .task { await store.loadMore() }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .contentMargins(.horizontal, LociTheme.defaultPadding, for: .scrollContent)
    .background(Color.lociPaper.ignoresSafeArea())
    .overlay { overlay }
    .navigationTitle("My reviews")
    .navigationDestination(for: LociReview.self) { ReviewedPlaceView(review: $0) }
    .sheet(item: $editing) { review in
      ReviewComposer(
        mode: .edit(review),
        placeName: review.placeName,
        onSubmit: { form, _ in await store.update(review, form: form) },
        onDelete: { await store.delete($0) },
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
    } message: { review in
      Text(review.placeName.isEmpty ? "This can't be undone." : "Your review of \(review.placeName) goes for good.")
    }
    .errorAlert(Binding(get: { editing == nil ? store.error : nil }, set: { store.error = $0 }))
    .refreshable { await store.load() }
    .task { if store.phase == .idle { await store.load() } }
    .onAppear { Analytics.screen("my_reviews") }
  }

  @ViewBuilder private var overlay: some View {
    switch store.phase {
    case .idle, .loading:
      ProgressView().accessibilityLabel("Loading your reviews")
    case .failed(let message):
      ContentUnavailableView {
        Label("Could not load your reviews", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("Try again") { Task { await store.load() } }.buttonStyle(.borderedProminent).tint(Color.lociForest)
      }
    case .loaded where store.reviews.isEmpty:
      ContentUnavailableView(
        "No reviews yet",
        systemImage: "star.bubble",
        description: Text("Open a place you've been to and tap Write a review.")
      )
    default: EmptyView()
    }
  }
}

/// A reviewed place's detail, opened from My reviews: the review's own name
/// first, then the stored place from GetPOI (the saved-place pattern).
struct ReviewedPlaceView: View {
  let review: LociReview
  @State private var stop: Loci_Poi_POIDetailedInfo
  @State private var loading = true

  init(review: LociReview) {
    self.review = review
    var stop = Loci_Poi_POIDetailedInfo()
    stop.id = review.poiID
    stop.name = review.placeName
    _stop = State(initialValue: stop)
  }

  var body: some View {
    PlaceDetailView(stop: stop, destination: .activities, cityName: stop.city)
      .navigationTitle(stop.name.isEmpty ? "Place" : stop.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if loading { ToolbarItem(placement: .topBarTrailing) { ProgressView().accessibilityLabel("Loading more details") } }
      }
      .task(id: review.poiID) {
        if !ResultsSideData.isOffline, var richer = await ReviewsAPI.place(poiID: review.poiID) {
          richer.id = review.poiID
          if richer.name.isEmpty { richer.name = review.placeName }
          withAnimation(.smooth) { stop = richer }
        }
        loading = false
      }
  }
}
