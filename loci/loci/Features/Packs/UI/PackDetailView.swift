import LociConnectProto
import SwiftUI

/// One pack and its claim. Four load states rather than a boolean, for web's
/// reason: "not loaded yet" must never read as either locked or unlocked.
@MainActor @Observable final class PackDetailStore {
  enum Phase: Equatable {
    case loading
    case loaded(PackDetail)
    /// NotFound: unpublished, retired, or a wrong slug.
    case unavailable
    case failed(String)
  }

  let slug: String
  private(set) var phase = Phase.loading
  private(set) var isClaiming = false
  private(set) var claimFailed = false
  /// The trip this screen already made. The server copies the pack again on
  /// every ClaimBundle, so a second tap opens this one instead of a duplicate.
  private(set) var claimedTripID: String?
  /// The trip to push; cleared when the editor is popped.
  var openTripID: String?

  private let service: PacksService

  init(slug: String, service: PacksService = ConnectPacksService()) {
    self.slug = slug
    self.service = service
  }

  var detail: PackDetail? {
    if case .loaded(let detail) = phase { return detail }
    return nil
  }

  func load() async {
    if detail == nil { phase = .loading }
    do {
      let detail = try await service.detail(slug: slug)
      let isFirstLoad = self.detail == nil
      phase = .loaded(detail)
      if isFirstLoad { Analytics.capture(.packViewed, ["slug": slug]) }
    } catch {
      if error is CancellationError || (error as? APIError) == .cancelled { return }
      // A refresh that fails keeps the pack on screen.
      guard detail == nil else { return }
      if case .notFound = error as? APIError { phase = .unavailable } else { phase = .failed(error.userMessage) }
    }
  }

  /// web: openAsTrip. ClaimBundle, then the new trip opens.
  func claim() async {
    guard let detail, detail.access == .unlocked, !isClaiming else { return }
    if let claimedTripID {
      openTripID = claimedTripID
      return
    }
    isClaiming = true
    claimFailed = false
    defer { isClaiming = false }
    do {
      let tripID = try await service.claim(bundleId: detail.pack.id)
      guard !tripID.isEmpty else {
        claimFailed = true
        return
      }
      Analytics.capture(.packClaimed, ["slug": slug])
      claimedTripID = tripID
      openTripID = tripID
    } catch {
      if error is CancellationError || (error as? APIError) == .cancelled { return }
      claimFailed = true
    }
  }
}

/// A City Pack (web: /packs/:slug): header, map hero, the days, then what
/// the caller can do with it. Opened from the catalog and by `loci://packs/:slug`.
struct PackDetailView: View {
  @State var store: PackDetailStore
  @State private var selectedID: String?
  @State private var detailPlace: Loci_Poi_POIDetailedInfo?
  @State private var showFullMap = false
  @Environment(\.dismiss) private var dismiss

  init(slug: String, service: PacksService = ConnectPacksService()) { _store = State(initialValue: PackDetailStore(slug: slug, service: service)) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        switch store.phase {
        case .loading: PackDetailSkeleton()
        case .loaded(let detail): content(detail)
        case .unavailable:
          ContentUnavailableView {
            Label("That pack is not available", systemImage: PacksView.symbol)
          } actions: {
            Button("Browse the others") { dismiss() }
          }
        case .failed(let message):
          ContentUnavailableView {
            Label("Could not load this pack", systemImage: "exclamationmark.triangle")
          } description: {
            Text(message)
          } actions: {
            Button("Try again") { Task { await store.load() } }.buttonStyle(.borderedProminent).tint(Color.lociForest)
          }
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(LociTheme.defaultPadding)
    }.background(Color.lociPaper.ignoresSafeArea()).navigationTitle(store.detail?.pack.title ?? "City Pack").navigationBarTitleDisplayMode(.inline)
      .refreshable { await store.load() }.task { if store.detail == nil { await store.load() } }.navigationDestination(item: $store.openTripID) {
        TripEditorView(tripID: $0)
      }.sheet(item: $detailPlace) { place in PlaceDetailSheet(stop: place, destination: .itinerary, cityName: store.detail?.pack.cityName ?? "") }
      .fullScreenCover(isPresented: $showFullMap) {
        if let detail = store.detail {
          FullMapView(
            data: Self.mapData(detail),
            groups: detail.groups,
            sequence: DayGrouping.sequence(detail.groups),
            destination: .itinerary,
            showsDays: true,
            title: detail.pack.cityName.isEmpty ? detail.pack.title : detail.pack.cityName,
            selectedID: $selectedID
          )
        }
      }.onAppear { Analytics.screen("pack_detail", ["slug": store.slug]) }
  }

  /// Pins numbered like the cards (so card 3 is pin 3 even when an earlier
  /// stop has no position) and coloured by the server's day.
  static func mapData(_ detail: PackDetail) -> ResultsMapData {
    let groups = detail.groups
    return ResultsMapData(groups: groups, extras: [], sequence: DayGrouping.sequence(groups), showsDays: true, alerts: [])
  }

  @ViewBuilder private func content(_ detail: PackDetail) -> some View {
    let groups = detail.groups
    let sequence = DayGrouping.sequence(groups)
    let mapData = Self.mapData(detail)

    PackHeader(pack: detail.pack)
    if !mapData.isEmpty { ResultsMapCard(data: mapData, selectedID: selectedID) { showFullMap = true } }
    if detail.unplacedCount > 0 {
      Text("\(detail.unplacedCount) of \(detail.stops.count) stops have no position yet and are not on the map.").font(.lociCaption(12))
        .foregroundStyle(Color.lociMutedInk)
    }
    ForEach(detail.days, id: \.dayNumber) { day in
      PackDaySection(day: day, sequence: sequence, selectedID: $selectedID) { stop in detailPlace = stop.detailPlace }
    }
    PackAccessCard(access: detail.access, isClaiming: store.isClaiming, hasTrip: store.claimedTripID != nil, claimFailed: store.claimFailed) {
      Task { await store.claim() }
    }
    if detail.pack.isPaid {
      Text("Written with AI assistance and checked by a person before publishing. Opening hours and prices change — confirm before you go.").font(
        .lociCaption(12)
      ).foregroundStyle(Color.lociMutedInk).multilineTextAlignment(.center).frame(maxWidth: .infinity)
    }
  }
}

// MARK: - Pieces

/// The `ResultsHeader` shape for a pack: city kicker, title, summary, tags.
private struct PackHeader: View {
  let pack: PackSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        if !pack.cityName.isEmpty { Text(pack.cityName).lociCoordStyle() }
        Text(pack.title).font(.lociDisplay(28)).foregroundStyle(Color.lociInk)
      }
      if !pack.summary.isEmpty { Text(pack.summary).font(.lociBody(15)).foregroundStyle(Color.lociMutedInk) }
      HStack(spacing: 8) {
        PackTags(pack: pack)
        if pack.badge == .yours { PackBadgeChip(badge: .yours) }
      }
    }
  }
}

/// One day: its header with the author's title, then the shared `StopCard`s
/// numbered across the pack, with the time to spend where the author gave one.
private struct PackDaySection: View {
  let day: PackDay
  let sequence: [String: Int]
  @Binding var selectedID: String?
  var onOpen: (PackStop) -> Void

  private var color: Color { LociTheme.dayColor(day.dayNumber) }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Circle().fill(color).frame(width: 10, height: 10)
        Text("Day \(day.dayNumber)").font(.lociHeadline(15)).foregroundStyle(Color.lociInk)
        if !day.title.isEmpty { Text(day.title).font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk).lineLimit(1) }
        Spacer(minLength: 4)
        Text("\(day.stops.count) \(day.stops.count == 1 ? "stop" : "stops")").lociCoordStyle(10)
      }.accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
      ForEach(day.stops, id: \.key) { stop in
        let card = stop.card
        StopCard(stop: card, index: sequence[card.stableID] ?? 0, color: color, destination: .itinerary, isSelected: selectedID == card.stableID) {
          selectedID = card.stableID
          onOpen(stop)
        }.overlay(alignment: .bottomTrailing) {
          if let time = stop.timeToSpend {
            Label(time, systemImage: "clock").font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk).padding(10).accessibilityLabel(
              "About \(time)"
            )
          }
        }
      }
    }
  }
}

/// What the caller can do: open it as a trip, or read how much is left.
/// The locked state has no price and no way to buy (App Store 3.1.1).
private struct PackAccessCard: View {
  let access: PackAccess
  let isClaiming: Bool
  let hasTrip: Bool
  let claimFailed: Bool
  let onClaim: () -> Void

  var body: some View {
    VStack(spacing: 10) {
      switch access {
      case .unlocked:
        Text("Make it yours").font(.lociHeadline(17)).foregroundStyle(Color.lociInk)
        Text("Open this pack as a trip you can edit, reorder and export. It becomes your own copy — later changes to the pack will not touch it.")
          .font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
        Button(action: onClaim) {
          HStack(spacing: 8) {
            if isClaiming {
              ProgressView().tint(Color.lociPaper)
              Text("Creating your trip…")
            } else {
              Text(hasTrip ? "Open my trip" : "Open as my trip")
              Image(systemName: "arrow.right")
            }
          }.frame(minHeight: 30)
        }.buttonStyle(.borderedProminent).tint(Color.lociForest).disabled(isClaiming)
        if claimFailed { Text("That did not save. Try again in a moment.").font(.lociCaption(13)).foregroundStyle(Color.lociDestructive) }
      case .locked(let days):
        Image(systemName: "lock.fill").foregroundStyle(Color.lociMutedInk).accessibilityHidden(true)
        Text("\(days) more \(days == 1 ? "day" : "days") in this pack").font(.lociHeadline(17)).foregroundStyle(Color.lociInk)
        Text("Day one is free to read. The other days are part of the full pack.").font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
      }
    }.multilineTextAlignment(.center).frame(maxWidth: .infinity).lociCard(padding: 20)
  }
}

/// Header, map and a day of cards, redacted, while the pack loads.
private struct PackDetailSkeleton: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Lisbon").lociCoordStyle()
        Text("Three slow days of tiles and tascas").font(.lociDisplay(28))
        Text("Day-by-day plans with real places, written and checked before they are published.").font(.lociBody(15))
      }
      RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous).fill(Color.lociMuted).frame(height: 260)
      ForEach(0..<3, id: \.self) { _ in
        RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous).fill(Color.lociMuted).frame(height: 108)
      }
    }.redacted(reason: .placeholder).accessibilityElement(children: .ignore).accessibilityLabel("Loading the pack")
  }
}
