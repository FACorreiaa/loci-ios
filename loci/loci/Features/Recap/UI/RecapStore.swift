import Foundation
import LociConnectProto
import Observation

/// One recap on screen: the owner's (by trip or by year) or a shared one (by code).
@MainActor @Observable final class RecapStore {
  enum Source: Equatable {
    case trip(id: String)
    case year(Int)
    case shared(code: String)
  }

  enum Phase: Equatable {
    case loading
    case ready
    /// The trip has no recap yet; the reason is written for the traveller.
    case ineligible(String)
    case failed(String)
  }

  private(set) var phase = Phase.loading
  private(set) var recap: Loci_Recap_Recap?
  /// A file or link ready for the share sheet.
  var sharing: RecapShareItem?
  private(set) var isPreparingShare = false
  var error: String?

  let source: Source
  private let service: any RecapService

  init(source: Source, service: any RecapService = ConnectRecapService()) {
    self.source = source
    self.service = service
  }

  var isOwner: Bool { if case .shared = source { false } else { true } }
  var isYear: Bool { if case .year = source { true } else { recap?.kind == .year } }
  var cards: [Loci_Recap_RecapCard] { RecapRules.playable(recap?.cards ?? []) }

  func load() async {
    do {
      let recap: Loci_Recap_Recap
      switch source {
      case .trip(let id): recap = try await service.tripRecap(tripID: id, refresh: false)
      case .year(let year): recap = try await service.yearInReview(year: year)
      case .shared(let code): recap = try await service.sharedRecap(code: code)
      }
      self.recap = recap
      guard recap.status == .ready, !RecapRules.playable(recap.cards).isEmpty else {
        let fallback = isYear ? "Your year in review unlocks on 1 December." : "Come back once the trip is over."
        phase = .ineligible(recap.ineligibleReason.isEmpty ? fallback : recap.ineligibleReason)
        return
      }
      phase = .ready
      if isOwner { await service.markViewed(recapID: recap.id) }
    } catch {
      guard !error.isCancellation else { return }
      phase = .failed(error.userMessage)
    }
  }

  /// The card as a story-sized image, for the share sheet.
  func shareImage(of card: Loci_Recap_RecapCard) async {
    guard let recap, !isPreparingShare else { return }
    isPreparingShare = true
    defer { isPreparingShare = false }
    do {
      let data = try await service.cardImage(recapID: recap.id, cardID: card.id)
      let name = "loci-\(recap.title)-\(card.id).png".replacingOccurrences(of: " ", with: "-")
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
      try data.write(to: url, options: .atomic)
      sharing = RecapShareItem(item: .file(url))
    } catch { self.error = error.userMessage }
  }

  /// The public link, minted on first use.
  func shareLink() async {
    guard let recap, !isPreparingShare else { return }
    isPreparingShare = true
    defer { isPreparingShare = false }
    let message = isYear ? "My \(recap.year) with Loci." : "My trip recap, made with Loci."
    do {
      sharing = RecapShareItem(item: .link(try await service.share(recapID: recap.id)), message: message)
    } catch { self.error = error.userMessage }
  }
}

struct RecapShareItem: Identifiable {
  enum Item {
    case file(URL)
    case link(URL)
  }

  let id = UUID()
  let item: Item
  var message = "My trip recap, made with Loci."

  var activityItems: [Any] {
    switch item {
    case .file(let url): [url]
    case .link(let url): [message, url]
    }
  }
}
