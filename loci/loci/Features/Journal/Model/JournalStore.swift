import Foundation
import LociConnectProto
import Observation
import SwiftProtobuf

/// Text the journal shows that the tests pin.
nonisolated enum JournalFormat {
  /// "Day 2 · Tue 21 Oct", or "Day 2" for an undated day. A day's date is a
  /// calendar date carried as midnight UTC, so it is read in UTC: in the
  /// traveller's zone it could be the day before.
  static func heading(_ day: Loci_Journal_JournalDay, locale: Locale = .current) -> String {
    let head = "Day \(day.dayNumber)"
    guard day.hasDate else { return head }
    let style = Date.FormatStyle(locale: locale, timeZone: .gmt).weekday(.abbreviated).day().month(.abbreviated)
    return "\(head) · \(day.date.date.formatted(style))"
  }

  /// How many planned stops were visited, as "2 of 5 visited".
  static func visited(_ day: Loci_Journal_JournalDay) -> String? {
    guard !day.stops.isEmpty else { return nil }
    return "\(day.stops.filter(\.hasVisitedAt).count) of \(day.stops.count) visited"
  }

  static func verdict(_ verdict: Loci_Ranking_Verdict) -> String? {
    switch verdict {
    case .loved: "Loved"
    case .fine: "Fine"
    case .notForMe: "Not for me"
    default: nil
    }
  }
}

/// One trip's journal on screen: load it, keep each day's note, add and
/// remove photos.
@MainActor @Observable final class JournalStore {
  enum Phase: Equatable {
    case loading
    case ready
    case failed(String)
  }

  private(set) var phase = Phase.loading
  private(set) var journal: Loci_Journal_TripJournal?
  /// Stays noticed on this trip waiting for "Were you here?".
  private(set) var pendingVisits: [PendingVisit] = []
  /// Day ids (or `tripKey`) with photos uploading.
  private(set) var uploading: Set<String> = []
  var error: String?

  static let tripKey = "trip"

  let tripID: String
  private let service: any JournalService
  private let uploader: PhotoUploader
  private let visits: PendingVisitStore
  private let recorder: any VisitRecorder

  init(
    tripID: String,
    service: any JournalService = ConnectJournalService(),
    session: URLSession = .shared,
    visits: PendingVisitStore = PendingVisitStore(),
    recorder: any VisitRecorder = ConnectVisitRecorder(),
  ) {
    self.tripID = tripID
    self.service = service
    uploader = PhotoUploader(service: service, session: session)
    self.visits = visits
    self.recorder = recorder
  }

  var photosEnabled: Bool { journal?.photosEnabled ?? false }

  func load() async {
    pendingVisits = visits.visits(tripID: tripID)
    do {
      journal = try await service.journal(tripID: tripID)
      phase = .ready
    } catch {
      guard !error.isCancellation else { return }
      if journal == nil { phase = .failed(error.userMessage) } else { self.error = error.userMessage }
    }
  }

  /// Saves a day's note when it changed. Shown at once; put back if the save fails.
  func saveDiary(dayID: String, text: String) async {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let index = journal?.days.firstIndex(where: { $0.dayID == dayID }),
      let before = journal?.days[index].diary, before != text
    else { return }
    journal?.days[index].diary = text
    do {
      let stored = try await service.setDiary(dayID: dayID, text: text)
      if let i = journal?.days.firstIndex(where: { $0.dayID == dayID }) { journal?.days[i].diary = stored }
    } catch {
      if let i = journal?.days.firstIndex(where: { $0.dayID == dayID }) { journal?.days[i].diary = before }
      self.error = error.userMessage
    }
  }

  /// Uploads photos one by one, then reloads so each lands where the server put it.
  func addPhotos(_ photos: [Data], dayID: String? = nil, stopID: String? = nil) async {
    guard !photos.isEmpty else { return }
    let key = dayID ?? Self.tripKey
    uploading.insert(key)
    defer { uploading.remove(key) }
    var failed = 0
    for data in photos {
      do {
        _ = try await uploader.upload(data, to: PhotoTarget(tripID: tripID, dayID: dayID, stopID: stopID))
      } catch {
        failed += 1
      }
    }
    if failed > 0 {
      error = failed == photos.count ? "Couldn't add those photos." : "\(failed) of \(photos.count) photos didn't upload."
    }
    await load()
  }

  /// "Yes, I was there": records the visit, then reloads so it shows on its day.
  func confirmVisit(id: String) async {
    do {
      try await visits.confirm(id: id, recorder: recorder)
      await load()
    } catch {
      self.error = error.userMessage
    }
  }

  func dismissVisit(id: String) {
    visits.dismiss(id: id)
    pendingVisits = visits.visits(tripID: tripID)
  }

  func deletePhoto(id: String) async {
    do {
      try await service.deletePhoto(id: id)
      await load()
    } catch {
      self.error = error.userMessage
    }
  }
}
