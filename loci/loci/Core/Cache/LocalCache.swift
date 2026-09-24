import Foundation
import SwiftProtobuf

/// Serialized protos on disk, one file per entry, so trips, saved places and
/// the day's forecast stay readable with no signal. Disposable: everything
/// here can be fetched again, so there is no schema and nothing to migrate.
/// Same storage rules as SearchStore: atomic writes, readable after the first
/// unlock so a background refresh can use it.
actor LocalCache {
  enum Kind: String, CaseIterable, Sendable { case trip, trips, saved, localContext, fx }

  static let shared = LocalCache()

  private let root: URL
  private var indexes: [Kind: [String: Date]] = [:]

  init(root: URL? = nil) {
    self.root =
      root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "loci/cache")
  }

  /// "41.903,12.496": the key for anything fetched for a coordinate.
  nonisolated static func key(latitude: Double, longitude: Double) -> String {
    String(format: "%.3f,%.3f", latitude, longitude)
  }

  func put<M: SwiftProtobuf.Message>(_ message: M, kind: Kind, id: String) throws {
    try FileManager.default.createDirectory(at: directory(kind), withIntermediateDirectories: true)
    try message.serializedData().write(to: file(kind, id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    var index = loadIndex(kind)
    index[id] = Date()
    saveIndex(kind, index)
  }

  func get<M: SwiftProtobuf.Message>(_ type: M.Type, kind: Kind, id: String) -> Cached<M>? {
    guard let fetchedAt = loadIndex(kind)[id], let data = try? Data(contentsOf: file(kind, id)),
      let value = try? M(serializedBytes: data)
    else { return nil }
    return Cached(value: value, fetchedAt: fetchedAt)
  }

  func ids(kind: Kind) -> [String] { loadIndex(kind).keys.sorted() }

  func remove(kind: Kind, id: String) {
    try? FileManager.default.removeItem(at: file(kind, id))
    var index = loadIndex(kind)
    index[id] = nil
    saveIndex(kind, index)
  }

  func clear() {
    try? FileManager.default.removeItem(at: root)
    indexes = [:]
  }

  // MARK: - Files

  private func directory(_ kind: Kind) -> URL { root.appending(path: kind.rawValue) }

  private func file(_ kind: Kind, _ id: String) -> URL {
    directory(kind).appending(path: id.replacingOccurrences(of: "/", with: "_") + ".bin")
  }

  private func indexURL(_ kind: Kind) -> URL { directory(kind).appending(path: "index.json") }

  private func loadIndex(_ kind: Kind) -> [String: Date] {
    if let cached = indexes[kind] { return cached }
    let decoded = (try? Data(contentsOf: indexURL(kind))).flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
    indexes[kind] = decoded
    return decoded
  }

  private func saveIndex(_ kind: Kind, _ index: [String: Date]) {
    indexes[kind] = index
    try? FileManager.default.createDirectory(at: directory(kind), withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(index) {
      try? data.write(to: indexURL(kind), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
  }
}

/// A cached value and when the server last gave it to us.
nonisolated struct Cached<M: Sendable>: Sendable {
  let value: M
  let fetchedAt: Date
}
