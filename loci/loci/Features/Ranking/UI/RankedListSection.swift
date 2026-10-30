import LociConnectProto
import SwiftUI

/// One city's ranked places as a List section: rank, verdict dot, name, 0–10.
struct RankedListSection: View {
  let title: String
  let places: [Loci_Ranking_RankedPlace]

  var body: some View {
    if !places.isEmpty {
      Section(title) {
        ForEach(places, id: \.poiID) { place in
          RankedPlaceRow(place: place)
        }
      }
    }
  }
}

struct RankedPlaceRow: View {
  let place: Loci_Ranking_RankedPlace

  private var dot: Color {
    switch place.verdict {
    case .loved: .lociForest
    case .notForMe: Color.lociDestructive.opacity(0.7)
    default: .lociMutedInk
    }
  }

  private var verdict: String {
    switch place.verdict {
    case .loved: RankingVerdict.loved.label
    case .notForMe: RankingVerdict.notForMe.label
    default: RankingVerdict.fine.label
    }
  }

  var body: some View {
    HStack(spacing: 10) {
      Text("\(place.rank)").font(.lociCoord(12)).foregroundStyle(Color.lociMutedInk).frame(minWidth: 22, alignment: .trailing)
      Circle().fill(dot).frame(width: 8, height: 8)
      Text(place.name).font(.lociCaption(15)).foregroundStyle(Color.lociInk).lineLimit(1)
      Spacer(minLength: 8)
      Text(place.score.formatted(.number.precision(.fractionLength(1))))
        .font(.lociHeadline(14)).foregroundStyle(Color.lociInk).monospacedDigit()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(place.rank). \(place.name), \(verdict), \(place.score.formatted(.number.precision(.fractionLength(1)))) out of 10")
  }
}

/// Loads one city's (or every city's) ranking for a section.
@MainActor @Observable final class RankingListStore {
  private(set) var places: [Loci_Ranking_RankedPlace] = []
  @ObservationIgnored private let service: any RankingService

  init(service: any RankingService = ConnectRankingService()) { self.service = service }

  func loadMine(city: String) async {
    places = (try? await service.mine(city: city)) ?? []
  }

  /// A friend's list; empty when the server refuses (not friends).
  func loadUser(id: String) async {
    places = (try? await service.user(id: id, city: "")) ?? []
  }

  func clear() { places = [] }
}
