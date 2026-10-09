import LociConnectProto
import SwiftUI

/// Contribute › Your reports: the scout's own field reports, newest first,
/// 20 a page (ListMyClaims).
@MainActor @Observable final class MyReportsStore {
  enum Phase: Equatable {
    case idle, loading, loaded
    case failed(String)
  }

  private(set) var claims: [MyClaim] = []
  private(set) var total = 0
  private(set) var phase = Phase.idle
  private(set) var hasMore = false
  private(set) var isLoadingMore = false
  private var page = 1
  var error: String?

  let service: ContributeService

  init(service: ContributeService = ConnectContributeService()) { self.service = service }

  func load() async {
    if claims.isEmpty { phase = .loading }
    do {
      let first = try await service.myClaims(page: 1)
      claims = first.claims
      total = first.total
      hasMore = first.hasMore
      page = 1
      phase = .loaded
    } catch {
      guard !error.isCancellation else {
        if phase == .loading { phase = .idle }
        return
      }
      if claims.isEmpty { phase = .failed(error.userMessage) } else { self.error = error.userMessage }
    }
  }

  /// The next page, skipping any report already shown (a new report shifts the pages).
  func loadMore() async {
    guard hasMore, !isLoadingMore, phase == .loaded else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let next = try await service.myClaims(page: page + 1)
      let known = Set(claims.map(\.id))
      claims += next.claims.filter { !known.contains($0.id) }
      hasMore = next.hasMore
      total = max(next.total, claims.count)
      page += 1
    } catch {
      if !error.isCancellation { self.error = error.userMessage }
    }
  }
}

struct MyReportsView: View {
  @State private var store: MyReportsStore

  init(store: MyReportsStore = MyReportsStore()) {
    _store = State(initialValue: store)
  }

  var body: some View {
    List {
      if store.phase == .loaded, store.total > 0 {
        Text("^[\(store.total) report](inflect: true)").lociCoordStyle(10)
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
      }
      ForEach(store.claims) { claim in
        VStack(alignment: .leading, spacing: 0) {
          if claim.opensPlace {
            NavigationLink(value: claim) { MyClaimRow(claim: claim) }
          } else {
            MyClaimRow(claim: claim)
          }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
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
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .task { await store.loadMore() }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .contentMargins(.horizontal, LociTheme.defaultPadding, for: .scrollContent)
    .background(Color.lociPaper)
    .overlay { overlay }
    .navigationTitle("Your reports")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(for: MyClaim.self) { ReviewedPlaceView(poiID: $0.poiID, placeName: $0.placeName) }
    .errorAlert($store.error)
    .refreshable { await store.load() }
    .task { if store.phase == .idle { await store.load() } }
    .onAppear { Analytics.screen("my_reports") }
  }

  @ViewBuilder private var overlay: some View {
    switch store.phase {
    case .idle, .loading:
      ProgressView().accessibilityLabel("Loading your reports")
    case .failed(let message):
      ContentUnavailableView {
        Label("Could not load your reports", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("Try again") { Task { await store.load() } }.lociProminentButton()
      }
    case .loaded where store.claims.isEmpty:
      ContentUnavailableView(
        "No reports yet",
        systemImage: "binoculars",
        description: Text("Answer a question about a place you know and it shows up here, with what became of it.")
      )
    default: EmptyView()
    }
  }
}

/// One of the scout's own reports: the place, the field and value, the
/// outcome and the day.
struct MyClaimRow: View {
  let claim: MyClaim

  private var when: String {
    guard let date = claim.createdAt else { return "" }
    return " · " + date.formatted(.dateTime.day().month(.abbreviated).year())
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: claim.symbol)
        .font(.body)
        .foregroundStyle(claim.status == .accepted ? Color.lociForest : Color.lociMutedInk)
        .frame(minWidth: 24)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(claim.placeName).font(.lociBody(15).weight(.semibold)).foregroundStyle(Color.lociInk)
        Text("\(claim.fieldLabel) · \(claim.valueText)").font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk).lineLimit(2)
        Text(claim.statusText + when).lociCoordStyle(10)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .lociCard()
    .accessibilityElement(children: .combine)
  }
}
