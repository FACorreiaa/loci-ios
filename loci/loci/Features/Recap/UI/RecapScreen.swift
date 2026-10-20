import SwiftUI

/// A recap pushed onto a tab's stack: the owner's, from a trip or its push
/// (`/recap/trip/:id`), their year (`/recap/year/:y`), or a shared one
/// (`/r/:code`). Loads, then plays.
struct RecapScreen: View {
  @State private var store: RecapStore
  @Environment(\.dismiss) private var dismiss

  init(source: RecapStore.Source, service: any RecapService = ConnectRecapService()) {
    _store = State(initialValue: RecapStore(source: source, service: service))
  }

  var body: some View {
    Group {
      switch store.phase {
      case .loading:
        ProgressView(store.isYear ? "Putting your year together…" : "Putting your trip together…").tint(RecapPalette.cream)
          .foregroundStyle(RecapPalette.cream).frame(
          maxWidth: .infinity,
          maxHeight: .infinity
        ).background(Color.black)
      case .ready: if let recap = store.recap { RecapStoryView(store: store, recap: recap) { dismiss() } }
      case .ineligible(let reason):
        ContentUnavailableView {
          Label(
            store.isYear ? "Your year isn't ready yet" : "Your recap isn't ready yet",
            systemImage: store.isYear ? "calendar" : "suitcase.rolling"
          )
        } description: {
          Text(reason)
        } actions: {
          Button(store.isYear ? "Back" : "Back to the trip") { dismiss() }
        }.background(Color.lociPaper.ignoresSafeArea())
      case .failed(let message):
        ContentUnavailableView {
          Label(failedTitle, systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          Button("Try again") { Task { await store.load() } }
        }.background(Color.lociPaper.ignoresSafeArea())
      }
    }.toolbar(store.phase == .ready ? .hidden : .automatic, for: .navigationBar).toolbar(.hidden, for: .tabBar).task {
      if store.phase == .loading { await store.load() }
    }
  }

  private var failedTitle: String {
    switch store.source {
    case .trip: "No recap for this trip"
    case .year: "Your year didn't load"
    case .shared: "This recap isn't shared any more"
    }
  }
}
