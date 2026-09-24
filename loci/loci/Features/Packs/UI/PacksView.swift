import SwiftUI

/// The catalog behind City Packs. A failure never reads as an empty catalog:
/// with nothing loaded it is an error with a retry (web shows nothing at all);
/// with cards already on screen for the same filters it is an alert and the
/// cards stay.
@MainActor @Observable final class PacksStore {
  enum Phase: Equatable {
    case loading, loaded
    case failed(String)
  }

  var filters = PackFilters()
  private(set) var packs: [PackSummary] = []
  private(set) var phase = Phase.loading
  var error: String?

  /// The filters `packs` was loaded for.
  private var loadedFilters: PackFilters?
  private let service: PacksService

  init(service: PacksService = ConnectPacksService()) { self.service = service }

  func load() async {
    let requested = filters
    let isRefresh = loadedFilters == requested && !packs.isEmpty
    if !isRefresh { phase = .loading }
    do {
      let page = try await service.list(requested)
      // A newer filter change owns the screen now.
      guard requested == filters else { return }
      packs = page.packs
      loadedFilters = requested
      phase = .loaded
    } catch {
      guard !(error is CancellationError), (error as? APIError) != .cancelled, requested == filters else { return }
      if isRefresh { self.error = error.userMessage } else { phase = .failed(error.userMessage) }
    }
  }

  func toggle(_ theme: PackTheme) { filters.theme = filters.theme == theme ? nil : theme }
  func toggle(month: Int) { filters.month = filters.month == month ? nil : month }
  func clearFilters() { filters = PackFilters() }
}

/// City Packs (web: /packs): day-by-day trips somebody already planned.
/// Entered from Discover. Filters are one theme, one month and Free only,
/// as on web; they stay on the screen rather than in a link.
struct PacksView: View {
  static let symbol = "shippingbox"

  @State var store: PacksStore
  @State private var showAllMonths = false
  private let currentMonth: Int

  init(store: PacksStore = PacksStore(), now: Date = Date(), calendar: Calendar = .current) {
    _store = State(initialValue: store)
    currentMonth = calendar.component(.month, from: now)
  }

  private var months: [Int] { showAllMonths ? Array(1...12) : PackMonths.upcoming(from: currentMonth) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        filters
        content
      }.padding(LociTheme.defaultPadding)
    }.background(Color.lociPaper.ignoresSafeArea()).navigationTitle("City Packs").navigationBarTitleDisplayMode(.inline).refreshable {
      await store.load()
    }.task(id: store.filters) { await store.load() }.errorAlert($store.error).onAppear { Analytics.screen("packs") }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("City Packs").lociCoordStyle(10)
      Text("Trips somebody already planned").font(.lociDisplay(28)).foregroundStyle(Color.lociInk)
      Text("Day-by-day guides for a city at the time of year it is worth going. Day one of every pack is free to read.").font(.lociBody(15))
        .foregroundStyle(Color.lociMutedInk)
    }
  }

  // MARK: - Filters

  private var filters: some View {
    VStack(alignment: .leading, spacing: 10) {
      FilterRow(title: "Taste") {
        ForEach(PackTheme.allCases) { theme in
          FilterChip(label: "\(theme.emoji) \(theme.label)", isOn: store.filters.theme == theme) { store.toggle(theme) }
        }
      }
      FilterRow(title: "When") {
        ForEach(months, id: \.self) { month in
          FilterChip(label: PackMonths.name(month), isOn: store.filters.month == month) { store.toggle(month: month) }
        }
        if !showAllMonths {
          Button("All months") { showAllMonths = true }.font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk).underline().frame(
            minHeight: LociTheme.minTapTarget
          )
        }
      }
      HStack(spacing: 12) {
        FilterChip(label: "Free only", isOn: store.filters.onlyFree) { store.filters.onlyFree.toggle() }
        if store.filters.isActive {
          Button("Clear filters") { store.clearFilters() }.font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk).underline().frame(
            minHeight: LociTheme.minTapTarget
          )
        }
        Spacer(minLength: 0)
      }
    }
  }

  // MARK: - Grid and states

  private let columns = [GridItem(.adaptive(minimum: 300), spacing: 12)]

  @ViewBuilder private var content: some View {
    switch store.phase {
    case .loading:
      LazyVGrid(columns: columns, spacing: 12) { ForEach(0..<6, id: \.self) { _ in PackCard(pack: .skeleton).redacted(reason: .placeholder) } }
        .accessibilityElement(children: .ignore).accessibilityLabel("Loading packs")
    case .failed(let message):
      ContentUnavailableView {
        Label("Could not load the City Packs", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("Try again") { Task { await store.load() } }.buttonStyle(.borderedProminent).tint(Color.lociForest)
      }
    case .loaded where store.packs.isEmpty:
      if store.filters.isActive {
        ContentUnavailableView {
          Label("No packs match those filters yet", systemImage: "line.3.horizontal.decrease")
        } actions: {
          Button("Clear filters") { store.clearFilters() }
        }
      } else {
        ContentUnavailableView(
          "No packs published yet",
          systemImage: Self.symbol,
          description: Text("They are written and checked by hand, so they arrive a few at a time.")
        )
      }
    case .loaded:
      LazyVGrid(columns: columns, spacing: 12) {
        ForEach(store.packs) { pack in
          NavigationLink {
            PackDetailView(slug: pack.slug)
          } label: {
            PackCard(pack: pack)
          }.buttonStyle(.plain)
        }
      }
    }
  }
}

// MARK: - Pieces

private struct FilterRow<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).lociCoordStyle(10)
      ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { content }.padding(.vertical, 2) }.scrollClipDisabled()
    }
  }
}

/// A single-select chip: tap again to clear (web: `aria-pressed` chips).
private struct FilterChip: View {
  let label: String
  let isOn: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(label).font(.lociCaption(13)).padding(.horizontal, 12).padding(.vertical, 7).background(
        isOn ? Color.lociForest : Color.lociMuted,
        in: Capsule()
      ).foregroundStyle(isOn ? Color.lociPaper : Color.lociInk).frame(minHeight: LociTheme.minTapTarget).contentShape(Capsule())
    }.buttonStyle(.plain).accessibilityAddTraits(isOn ? .isSelected : [])
  }
}

/// One pack in the grid (web: components/packs/PackCard.tsx), minus the price.
struct PackCard: View {
  let pack: PackSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(pack.cityName).lociCoordStyle(10)
          Text(pack.title).font(.lociHeadline(17)).foregroundStyle(Color.lociInk).multilineTextAlignment(.leading)
        }
        Spacer(minLength: 0)
        PackBadgeChip(badge: pack.badge)
      }
      if !pack.summary.isEmpty {
        Text(pack.summary).font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk).lineLimit(2).multilineTextAlignment(.leading)
      }
      PackTags(pack: pack)
    }.frame(maxWidth: .infinity, alignment: .leading).lociCard().accessibilityElement(children: .combine).accessibilityHint("Opens the pack")
  }
}

/// Free / ✓ Yours / a lock. The lock never carries a price.
struct PackBadgeChip: View {
  let badge: PackBadge

  var body: some View {
    HStack(spacing: 4) {
      if let symbol = badge.systemImage { Image(systemName: symbol).font(.caption2.weight(.bold)) }
      Text(badge.label)
    }.font(.lociCaption(12)).foregroundStyle(badge == .locked ? Color.lociMutedInk : Color.lociForest).padding(.horizontal, 8).padding(.vertical, 4)
      .background(badge == .locked ? Color.lociMuted : Color.lociSage, in: Capsule()).fixedSize()
  }
}

/// Theme, months, and "3 days · 12 stops".
struct PackTags: View {
  let pack: PackSummary

  var body: some View {
    HStack(spacing: 6) {
      Tag(text: PackTheme.label(for: pack.theme))
      Tag(text: PackMonths.label(pack.months))
      Label(pack.sizeLabel, systemImage: "mappin").font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk).lineLimit(1)
    }
  }

  private struct Tag: View {
    let text: String

    var body: some View {
      Text(text).font(.lociCaption(12)).foregroundStyle(Color.lociInk).lineLimit(1).padding(.horizontal, 8).padding(.vertical, 3).background(
        Color.lociMuted,
        in: Capsule()
      )
    }
  }
}

nonisolated extension PackSummary {
  /// Placeholder text for the redacted skeleton cards.
  static let skeleton = PackSummary(
    id: "skeleton",
    slug: "skeleton",
    title: "Three slow days of tiles and tascas",
    summary: "Day-by-day plans with real places, written and checked before they are published.",
    cityName: "Lisbon",
    theme: "food",
    months: [4, 5, 6],
    dayCount: 3,
    stopCount: 12
  )
}
