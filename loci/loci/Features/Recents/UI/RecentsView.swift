import LociConnectProto
import SwiftUI

/// The feed and the cities behind Recents. A failure never reads as an empty
/// history: with nothing loaded it is an error with a retry; with rows on
/// screen it is an alert and the rows stay.
@MainActor @Observable final class RecentsStore {
  enum Phase: Equatable {
    case idle, loading, loaded
    case failed(String)
  }

  private(set) var entries: [ActivityEntry] = []
  private(set) var hasMore = false
  private(set) var feedPhase = Phase.idle
  private(set) var isLoadingMore = false
  private(set) var pages = 1
  private(set) var cities: [RecentCity] = []
  private(set) var citiesPhase = Phase.idle
  /// Captured per load, so the day headings are a pure function of what loaded.
  private(set) var now: Date
  var error: String?

  private let service: RecentsService

  init(service: RecentsService = ConnectRecentsService(), now: Date = Date()) {
    self.service = service
    self.now = now
  }

  private var userId: String { AuthSessionManager.shared.currentUserID ?? "me" }

  func loadIfNeeded(_ segment: RecentsView.Segment) async {
    switch segment {
    case .feed: if feedPhase == .idle { await loadFeed() }
    case .cities: if citiesPhase == .idle { await loadCities() }
    }
  }

  func reload(_ segment: RecentsView.Segment) async {
    switch segment {
    case .feed: await loadFeed()
    case .cities: await loadCities()
    }
  }

  /// Every loaded page again, from the top: something new arriving keeps the order right.
  func loadFeed() async {
    if entries.isEmpty { feedPhase = .loading }
    do {
      let page = try await service.activity(userId: userId, pages: pages)
      entries = page.entries
      hasMore = page.hasMore
      now = Date()
      feedPhase = .loaded
    } catch {
      guard !Self.isCancellation(error) else {
        if feedPhase == .loading { feedPhase = .idle }
        return
      }
      if entries.isEmpty { feedPhase = .failed(error.userMessage) } else { self.error = error.userMessage }
    }
  }

  /// "Load more" asks for one more page's worth from offset 0 (web: 40 × pages).
  func loadMore() async {
    guard hasMore, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let page = try await service.activity(userId: userId, pages: pages + 1)
      pages += 1
      entries = page.entries
      hasMore = page.hasMore
    } catch {
      if !Self.isCancellation(error) { self.error = error.userMessage }
    }
  }

  func loadCities() async {
    if cities.isEmpty { citiesPhase = .loading }
    do {
      cities = try await service.cities(userId: userId)
      now = Date()
      citiesPhase = .loaded
    } catch {
      guard !Self.isCancellation(error) else {
        if citiesPhase == .loading { citiesPhase = .idle }
        return
      }
      if cities.isEmpty { citiesPhase = .failed(error.userMessage) } else { self.error = error.userMessage }
    }
  }

  private static func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || (error as? APIError) == .cancelled
  }
}

/// Recents (web: /recents): what you did, newest first, and the cities you did it in.
struct RecentsView: View {
  enum Segment: String, CaseIterable { case feed = "Feed", cities = "Cities" }

  @State var store: RecentsStore
  @State private var segment: Segment
  @State private var typeId = "all"
  @State private var query = ""
  private let router = AppRouter.shared

  init(store: RecentsStore = RecentsStore(), segment: Segment = .feed) {
    _store = State(initialValue: store)
    _segment = State(initialValue: segment)
  }

  private var visible: [ActivityEntry] { ActivityFilter.apply(store.entries, typeId: typeId, query: query) }
  private var isFiltered: Bool { typeId != "all" || !query.trimmingCharacters(in: .whitespaces).isEmpty }
  private var visibleCities: [RecentCity] { RecentCities.filter(store.cities, query: query) }

  var body: some View {
    List {
      Picker("View", selection: $segment) { ForEach(Segment.allCases, id: \.self) { Text($0.rawValue) } }
        .pickerStyle(.segmented)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())

      switch segment {
      case .feed: feed
      case .cities: citiesList
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(Color.lociPaper.ignoresSafeArea())
    .overlay { overlay }
    .searchable(text: $query, prompt: segment == .feed ? "Search your activity…" : "Search cities…")
    .navigationTitle("Recents")
    .navigationDestination(for: ActivityDestination.self) { ActivityDestinationView(destination: $0) }
    .navigationDestination(for: RecentCity.self) { RecentCityView(city: $0) }
    .refreshable { await store.reload(segment) }
    .task(id: segment) { await store.loadIfNeeded(segment) }
    .errorAlert($store.error)
    .onAppear { Analytics.screen("recents") }
  }

  // MARK: - Feed

  @ViewBuilder private var feed: some View {
    switch store.feedPhase {
    case .idle, .loading: SkeletonRows()
    case .failed: EmptyView()
    case .loaded:
      if !store.entries.isEmpty {
        ActivityTypeChips(selection: $typeId, counts: ActivityFilter.counts(store.entries))
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())
      }
      ForEach(DayBuckets.bucket(visible, now: store.now)) { group in
        Section(group.label) {
          ForEach(group.entries) { entry in
            ActivityRowLink(entry: entry, now: store.now)
          }
        }
        .listRowBackground(Color.lociCard)
      }
      if store.hasMore {
        Section {
          Button {
            Task { await store.loadMore() }
          } label: {
            HStack {
              Spacer()
              if store.isLoadingMore { ProgressView() } else { Text("Load more") }
              Spacer()
            }
          }
          .disabled(store.isLoadingMore)
        }
        .listRowBackground(Color.lociCard)
      }
      if store.entries.count >= ActivityFeed.pageSize {
        Text("Showing your \(store.entries.count) most recent actions.")
          .font(.lociCaption())
          .foregroundStyle(Color.lociMutedInk)
          .frame(maxWidth: .infinity)
          .listRowBackground(Color.clear)
      }
    }
  }

  // MARK: - Cities

  @ViewBuilder private var citiesList: some View {
    switch store.citiesPhase {
    case .idle, .loading: SkeletonRows()
    case .failed: EmptyView()
    case .loaded:
      if !visibleCities.isEmpty {
        Section(visibleCities.count == 1 ? "1 city" : "\(visibleCities.count) cities") {
          ForEach(visibleCities) { city in
            NavigationLink(value: city) { CityRow(city: city, now: store.now) }
          }
        }
        .listRowBackground(Color.lociCard)
      }
    }
  }

  // MARK: - Empty and error states (web copy)

  @ViewBuilder private var overlay: some View {
    switch segment {
    case .feed:
      if case .failed = store.feedPhase {
        RecentsError(title: "Could not load your activity", message: "The history is still there. This is on our side.", retry: "Try again") {
          Task { await store.loadFeed() }
        }
      } else if store.feedPhase == .loaded, visible.isEmpty {
        if isFiltered {
          ContentUnavailableView(
            "Nothing of that kind yet",
            systemImage: "line.3.horizontal.decrease",
            description: Text("Try another type, or clear the search.")
          )
        } else {
          RecentsEmpty(
            title: "No activity yet",
            message: "Everything you ask, save or favourite shows up here.",
            action: "Start exploring"
          ) { router.selectedTab = .discover }
        }
      }
    case .cities:
      if case .failed = store.citiesPhase {
        RecentsError(title: "Unable to load recent activity", message: "Please try again later", retry: "Try again") {
          Task { await store.loadCities() }
        }
      } else if store.citiesPhase == .loaded, visibleCities.isEmpty {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
          RecentsEmpty(
            title: "No recent activity",
            message: "Start exploring cities to see your activity here!",
            action: "Start exploring"
          ) { router.selectedTab = .discover }
        } else {
          ContentUnavailableView("No cities found", systemImage: "magnifyingglass", description: Text("Try adjusting your search."))
        }
      }
    }
  }
}

// MARK: - Pieces

/// A feed row, and where it goes. A kind this build does not know opens nothing.
private struct ActivityRowLink: View {
  let entry: ActivityEntry
  let now: Date

  var body: some View {
    if let destination = ActivityDestination(entry) {
      NavigationLink(value: destination) { ActivityRow(entry: entry, now: now) }
    } else {
      ActivityRow(entry: entry, now: now)
    }
  }
}

/// Badge, what was asked or kept, kind and city, and how long ago (web: ActivityRow).
struct ActivityRow: View {
  let entry: ActivityEntry
  let now: Date

  private var badge: ActivityBadge { ActivityBadge(entry) }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      RecentsBadgeIcon(systemImage: badge.systemImage)
      VStack(alignment: .leading, spacing: 3) {
        Text(entry.label.isEmpty ? badge.label : entry.label)
          .font(.lociHeadline(16))
          .foregroundStyle(Color.lociInk)
          .lineLimit(2)
        HStack(spacing: 6) {
          Text(badge.label)
          if !entry.cityName.isEmpty {
            Text("·").accessibilityHidden(true)
            Text(entry.cityName).lineLimit(1)
          }
        }
        .lociCoordStyle(10)
      }
      Spacer(minLength: 8)
      Text(DayBuckets.relativeTime(entry.occurredAt, now: now))
        .font(.lociCaption())
        .foregroundStyle(Color.lociMutedInk)
        .lineLimit(1)
        .fixedSize()
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}

/// A city in the Cities view: name, count and badge, the latest prompt, when.
private struct CityRow: View {
  let city: RecentCity
  let now: Date

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      RecentsBadgeIcon(systemImage: city.level.systemImage)
      VStack(alignment: .leading, spacing: 3) {
        Text(city.name).font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
        HStack(spacing: 6) {
          Text(city.interactionCount == 1 ? "1 interaction" : "\(city.interactionCount) interactions")
          Text("·").accessibilityHidden(true)
          Text(city.level.label)
        }
        .lociCoordStyle(10)
        if let latest = city.interactions.first {
          Text("Latest: \(latest.prompt)").font(.lociCaption()).foregroundStyle(Color.lociMutedInk).lineLimit(2)
        }
      }
      Spacer(minLength: 8)
      Text(DayBuckets.relativeTime(city.lastActivity, now: now))
        .font(.lociCaption())
        .foregroundStyle(Color.lociMutedInk)
        .lineLimit(1)
        .fixedSize()
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}

struct RecentsBadgeIcon: View {
  let systemImage: String

  var body: some View {
    Image(systemName: systemImage)
      .font(.system(size: 14, weight: .medium))
      .foregroundStyle(Color.lociForest)
      .frame(width: 32, height: 32)
      .background(Color.lociMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .accessibilityHidden(true)
  }
}

/// Horizontal type chips with their counts over what has loaded.
private struct ActivityTypeChips: View {
  @Binding var selection: String
  let counts: [String: Int]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(ActivityTypeOption.all) { option in
          let isOn = selection == option.id
          Button {
            selection = option.id
          } label: {
            HStack(spacing: 5) {
              Text(option.label)
              if option.id != "all" { Text("\(counts[option.id] ?? 0)").monospacedDigit().opacity(0.7) }
            }
            .font(.lociCaption(13))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isOn ? Color.lociForest : Color.lociMuted, in: Capsule())
            .foregroundStyle(isOn ? Color.lociPaper : Color.lociInk)
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(isOn ? .isSelected : [])
        }
      }
      .padding(.horizontal, 4)
      .padding(.vertical, 4)
    }
    .accessibilityLabel("Filter activity by type")
  }
}

/// Six placeholder rows while the first page loads.
private struct SkeletonRows: View {
  var body: some View {
    Section {
      ForEach(0..<6, id: \.self) { _ in
        HStack(alignment: .top, spacing: 12) {
          RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.lociMuted).frame(width: 32, height: 32)
          VStack(alignment: .leading, spacing: 6) {
            Text("Three days in Porto with the kids").font(.lociHeadline(16))
            Text("Itinerary · Porto").font(.lociCaption())
          }
        }
        .redacted(reason: .placeholder)
      }
    }
    .listRowBackground(Color.lociCard)
    .accessibilityLabel("Loading")
  }
}

private struct RecentsError: View {
  let title: String
  let message: String
  let retry: String
  let onRetry: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label(title, systemImage: "exclamationmark.triangle")
    } description: {
      Text(message)
    } actions: {
      Button(retry, action: onRetry).buttonStyle(.borderedProminent).tint(Color.lociForest)
    }
  }
}

private struct RecentsEmpty: View {
  let title: String
  let message: String
  let action: String
  let onAction: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label(title, systemImage: "clock.arrow.circlepath")
    } description: {
      Text(message)
    } actions: {
      Button(action, systemImage: "sparkles", action: onAction).buttonStyle(.borderedProminent).tint(Color.lociForest)
    }
  }
}

/// The page a feed row opens.
struct ActivityDestinationView: View {
  let destination: ActivityDestination

  var body: some View {
    switch destination {
    case let .search(link, message): SearchResultsView(link: link, rerunMessage: message)
    case .nearby: NearbyView()
    case let .savedItinerary(id, sessionId): SavedItineraryLoader(id: id, sessionId: sessionId)
    case .favourite(let item): SavedPlaceDetailView(item: item)
    }
  }
}

/// A kept itinerary from the feed: found in the Saved list by id or session.
/// Gone from the list, it falls back to the session that made it, if any.
private struct SavedItineraryLoader: View {
  let id: String
  let sessionId: String

  enum Phase { case loading, found(Loci_Itinerary_UserSavedItinerary), missing, failed(String) }

  @State private var phase = Phase.loading
  private let router = AppRouter.shared

  var body: some View {
    Group {
      switch phase {
      case .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      case .found(let itinerary): SavedItineraryView(itinerary: itinerary)
      case .missing:
        if sessionId.isEmpty {
          ContentUnavailableView {
            Label("Not in your saved itineraries", systemImage: "bookmark.slash")
          } description: {
            Text("It may have been removed.")
          } actions: {
            Button("Open Saved") { router.selectedTab = .saved }
          }
        } else {
          SearchResultsView(link: SessionLink(destination: .itinerary, sessionId: sessionId, domain: "itinerary"))
        }
      case .failed(let message):
        RecentsError(title: "Could not load this itinerary", message: message, retry: "Try again") { Task { await load() } }
      }
    }
    .background(Color.lociPaper.ignoresSafeArea())
    .task { await load() }
  }

  private func load() async {
    phase = .loading
    do {
      phase = try await RecentsAPI.savedItinerary(id: id, sessionId: sessionId).map(Phase.found) ?? .missing
    } catch {
      if (error as? APIError) != .cancelled { phase = .failed(error.userMessage) }
    }
  }
}
