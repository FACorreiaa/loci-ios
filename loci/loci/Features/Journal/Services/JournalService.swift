import Foundation
import LociConnectProto

/// Where a signed photo upload goes. The PUT must carry `headers`: the type
/// and length are part of the signature.
nonisolated struct PhotoUploadTicket: Sendable, Equatable {
  let photoID: String
  let url: URL
  let headers: [String: String]
}

/// What a photo belongs to: the whole trip, a day, or a stop on a day.
nonisolated struct PhotoTarget: Sendable, Equatable {
  let tripID: String
  var dayID: String?
  var stopID: String?
}

/// JournalService (loci.journal): a trip told day by day, with the
/// traveller's notes and photos. Web: lib/api/journal.ts.
protocol JournalService: Sendable {
  func journal(tripID: String) async throws -> Loci_Journal_TripJournal
  /// Saves a day's note; returns it as stored (trimmed). Empty clears it.
  func setDiary(dayID: String, text: String) async throws -> String
  func createUpload(_ target: PhotoTarget, contentType: String, size: Int) async throws -> PhotoUploadTicket
  func confirm(photoID: String, caption: String) async throws -> Loci_Journal_TripPhoto
  func deletePhoto(id: String) async throws
}

nonisolated struct ConnectJournalService: JournalService {
  private static let client = Loci_Journal_JournalServiceClient(client: ConnectTransport.shared.protocolClient)

  func journal(tripID: String) async throws -> Loci_Journal_TripJournal {
    var request = Loci_Journal_GetTripJournalRequest()
    request.tripID = tripID
    return try await rpc("Could not load the journal.", request) { await Self.client.getTripJournal(request: $0, headers: [:]) }.journal
  }

  func setDiary(dayID: String, text: String) async throws -> String {
    var request = Loci_Journal_SetDayDiaryRequest()
    request.dayID = dayID
    request.text = text
    return try await rpc("Could not save that note.", request) { await Self.client.setDayDiary(request: $0, headers: [:]) }.diary
  }

  func createUpload(_ target: PhotoTarget, contentType: String, size: Int) async throws -> PhotoUploadTicket {
    var request = Loci_Journal_CreatePhotoUploadRequest()
    request.tripID = target.tripID
    if let dayID = target.dayID { request.dayID = dayID }
    if let stopID = target.stopID { request.stopID = stopID }
    request.contentType = contentType
    request.sizeBytes = Int64(size)
    let response = try await rpc("Could not add that photo.", request) { await Self.client.createPhotoUpload(request: $0, headers: [:]) }
    guard let url = URL(string: response.uploadURL) else { throw APIError.server("Could not add that photo.") }
    return PhotoUploadTicket(photoID: response.photoID, url: url, headers: response.headers)
  }

  func confirm(photoID: String, caption: String) async throws -> Loci_Journal_TripPhoto {
    var request = Loci_Journal_ConfirmPhotoRequest()
    request.photoID = photoID
    request.caption = caption
    return try await rpc("Could not add that photo.", request) { await Self.client.confirmPhoto(request: $0, headers: [:]) }.photo
  }

  func deletePhoto(id: String) async throws {
    var request = Loci_Journal_DeletePhotoRequest()
    request.photoID = id
    _ = try await rpc("Could not remove that photo.", request) { await Self.client.deletePhoto(request: $0, headers: [:]) }
  }
}
