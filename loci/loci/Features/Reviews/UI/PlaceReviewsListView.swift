import SwiftUI

/// Every review of one place, newest first, a page at a time ("See all").
/// Shares its store with the place's Reviews section, so votes and your own
/// edits agree between the two.
struct PlaceReviewsListView: View {
  let store: PlaceReviewsStore
  @State private var composer: ReviewComposerMode?
  @State private var pendingDelete: LociReview?

  var body: some View {
    List {
      Section {
        ReviewSummary(stats: store.stats)
          .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
      }
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
      Section {
        ForEach(store.reviews) { review in
          PlaceReviewCard(store: store, review: review, composer: $composer, pendingDelete: $pendingDelete)
            .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
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
          .task { await store.loadMore() }
        }
      }
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .contentMargins(.horizontal, LociTheme.defaultPadding, for: .scrollContent)
    .background(Color.lociPaper.ignoresSafeArea())
    .overlay {
      if store.phase == .loaded, store.reviews.isEmpty {
        ContentUnavailableView("No reviews yet", systemImage: "star.bubble", description: Text("Be the first to say how it was."))
      }
    }
    .navigationTitle(store.placeName.isEmpty ? "Reviews" : store.placeName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) { WriteReviewButton(store: store, composer: $composer).labelStyle(.titleOnly) }
    }
    .refreshable { await store.load() }
    .reviewActions(store: store, composer: $composer, pendingDelete: $pendingDelete)
    .onAppear { Analytics.screen("place_reviews") }
  }
}
