import CoreGraphics
import Foundation
import ImageIO
import LociConnectProto
import SwiftProtobuf
import Testing
import UniformTypeIdentifiers

@testable import loci

/// A journal service that records calls and fails on request.
nonisolated final class StubJournalService: JournalService, @unchecked Sendable {
  private let lock = NSLock()
  private var _calls: [String] = []
  var calls: [String] { lock.withLock { _calls } }
  var journal = Loci_Journal_TripJournal()
  var failDiary = false
  var failConfirm = false
  var ticketURL = URL(string: "https://media.lociai.fyi/loci-media/trips/t1/p1.jpg?sig") ?? URL(filePath: "/")
  var lastSize = 0

  private func record(_ call: String) { lock.withLock { _calls.append(call) } }

  func journal(tripID: String) async throws -> Loci_Journal_TripJournal {
    record("journal")
    return journal
  }

  func setDiary(dayID: String, text: String) async throws -> String {
    record("diary")
    if failDiary { throw APIError.server("down") }
    return text
  }

  func createUpload(_ target: PhotoTarget, contentType: String, size: Int) async throws -> PhotoUploadTicket {
    record("create")
    lock.withLock { lastSize = size }
    return PhotoUploadTicket(
      photoID: "p1",
      url: ticketURL,
      headers: ["Content-Type": contentType, "Content-Length": "\(size)", "Host": "media.lociai.fyi"],
    )
  }

  func confirm(photoID: String, caption: String) async throws -> Loci_Journal_TripPhoto {
    record("confirm")
    if failConfirm { throw APIError.server("mismatch") }
    var photo = Loci_Journal_TripPhoto()
    photo.id = photoID
    return photo
  }

  func deletePhoto(id: String) async throws { record("delete") }
}

/// Answers every request with `status` and keeps the last request seen.
nonisolated final class StubUploadProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var status = 200
  nonisolated(unsafe) static var lastRequest: URLRequest?

  override static func canInit(with request: URLRequest) -> Bool { true }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lastRequest = request
    guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: Self.status, httpVersion: nil, headerFields: nil) else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data())
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  static func session() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubUploadProtocol.self]
    return URLSession(configuration: config)
  }
}

/// A 4032×3024 PNG, the shape of a phone photo.
private func photoData(width: Int = 4032, height: Int = 3024) -> Data {
  let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
  )
  context?.setFillColor(CGColor(red: 0.9, green: 0.4, blue: 0.3, alpha: 1))
  context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
  let out = NSMutableData()
  if let image = context?.makeImage(), let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) {
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
  }
  return out as Data
}

struct ImageResizeTests {
  @Test func fitsTheLongEdge() {
    #expect(ImageResize.fit(CGSize(width: 4032, height: 3024), maxEdge: 2048) == CGSize(width: 2048, height: 1536))
    #expect(ImageResize.fit(CGSize(width: 3024, height: 4032), maxEdge: 2048) == CGSize(width: 1536, height: 2048))
  }

  @Test func neverScalesUp() {
    #expect(ImageResize.fit(CGSize(width: 800, height: 600), maxEdge: 2048) == CGSize(width: 800, height: 600))
  }

  @Test func reencodesAsASmallerJPEG() throws {
    let jpeg = try #require(ImageResize.jpeg(from: photoData()))
    let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
    #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    #expect(props[kCGImagePropertyPixelWidth] as? Int == 2048)
    #expect(props[kCGImagePropertyGPSDictionary] == nil)
  }

  @Test func refusesNonImages() {
    #expect(ImageResize.jpeg(from: Data("not a photo".utf8)) == nil)
  }
}

@Suite(.serialized) struct PhotoUploaderTests {
  @Test func putsWithTheSignedHeadersThenConfirms() async throws {
    StubUploadProtocol.status = 200
    let service = StubJournalService()
    let uploader = PhotoUploader(service: service, session: StubUploadProtocol.session())
    let photo = try await uploader.upload(photoData(), to: PhotoTarget(tripID: "t1", dayID: "d1"))
    #expect(photo.id == "p1")
    #expect(service.calls == ["create", "confirm"])
    let request = try #require(StubUploadProtocol.lastRequest)
    #expect(request.httpMethod == "PUT")
    #expect(request.url == service.ticketURL)
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
  }

  @Test func failedPutDeletesThePendingPhoto() async {
    StubUploadProtocol.status = 403
    let service = StubJournalService()
    let uploader = PhotoUploader(service: service, session: StubUploadProtocol.session())
    await #expect(throws: (any Error).self) { try await uploader.upload(photoData(), to: PhotoTarget(tripID: "t1")) }
    #expect(service.calls == ["create", "delete"])
  }

  @Test func failedConfirmDeletesThePendingPhoto() async {
    StubUploadProtocol.status = 200
    let service = StubJournalService()
    service.failConfirm = true
    let uploader = PhotoUploader(service: service, session: StubUploadProtocol.session())
    await #expect(throws: (any Error).self) { try await uploader.upload(photoData(), to: PhotoTarget(tripID: "t1")) }
    #expect(service.calls == ["create", "confirm", "delete"])
  }

  @Test func notAPhotoNeverReachesTheServer() async {
    let service = StubJournalService()
    let uploader = PhotoUploader(service: service, session: StubUploadProtocol.session())
    await #expect(throws: (any Error).self) { try await uploader.upload(Data("x".utf8), to: PhotoTarget(tripID: "t1")) }
    #expect(service.calls.isEmpty)
  }
}

@MainActor struct JournalStoreTests {
  private func journal() -> Loci_Journal_TripJournal {
    var day = Loci_Journal_JournalDay()
    day.dayID = "d1"
    day.dayNumber = 1
    day.diary = "Rain."
    var journal = Loci_Journal_TripJournal()
    journal.tripID = "t1"
    journal.days = [day]
    return journal
  }

  @Test func loads() async {
    let service = StubJournalService()
    service.journal = journal()
    let store = JournalStore(tripID: "t1", service: service)
    await store.load()
    #expect(store.phase == .ready)
    #expect(store.journal?.days.first?.diary == "Rain.")
  }

  @Test func diarySaveRollsBackOnFailure() async {
    let service = StubJournalService()
    service.journal = journal()
    service.failDiary = true
    let store = JournalStore(tripID: "t1", service: service)
    await store.load()
    await store.saveDiary(dayID: "d1", text: "Sun at last.")
    #expect(store.journal?.days.first?.diary == "Rain.")
    #expect(store.error != nil)
  }

  @Test func unchangedDiaryIsNotSent() async {
    let service = StubJournalService()
    service.journal = journal()
    let store = JournalStore(tripID: "t1", service: service)
    await store.load()
    await store.saveDiary(dayID: "d1", text: "  Rain.  ")
    #expect(!service.calls.contains("diary"))
  }

  @Test func headingReadsTheDateInUTC() throws {
    var day = Loci_Journal_JournalDay()
    day.dayNumber = 1
    // Midnight UTC on Tue 20 Oct: the 19th anywhere west of UTC.
    day.date = Google_Protobuf_Timestamp(date: try #require(ISO8601DateFormatter().date(from: "2026-10-20T00:00:00Z")))
    #expect(JournalFormat.heading(day, locale: Locale(identifier: "en_GB")) == "Day 1 · Tue 20 Oct")
    day.clearDate()
    #expect(JournalFormat.heading(day) == "Day 1")
  }
}
