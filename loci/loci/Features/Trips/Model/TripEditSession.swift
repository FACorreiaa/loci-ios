import Connect
import Foundation
import LociConnectProto
import Observation

/// The calls a result page makes to the trip behind it. A value of closures so
/// tests hand in their own.
nonisolated struct TripEditClient: Sendable {
  typealias Trip = Loci_Trip_TripDraft
  typealias Stop = Loci_Trip_TripStop

  var trip: @Sendable (_ id: String) async throws(TripRPCError) -> Trip
  var tripForSession: @Sendable (_ sessionID: String) async throws(TripRPCError) -> Trip?
  var reorder: @Sendable (_ tripID: String, _ dayID: String, _ stopIDs: [String], _ version: Int64) async throws(TripRPCError) -> Trip
  var move: @Sendable (_ tripID: String, _ stopID: String, _ toDayID: String, _ toIndex: Int, _ version: Int64) async throws(TripRPCError) -> Trip
  var remove: @Sendable (_ tripID: String, _ stopID: String, _ version: Int64) async throws(TripRPCError) -> Trip
  var add: @Sendable (_ tripID: String, _ dayID: String, _ stop: Stop, _ afterStopID: String?, _ version: Int64) async throws(TripRPCError) -> Trip

  static let live = TripEditClient(
    trip: { id throws(TripRPCError) in try await TripAPI.trip(id: id) },
    tripForSession: { id throws(TripRPCError) in try await TripAPI.tripForSession(id) },
    reorder: { trip, day, ids, version throws(TripRPCError) in
      try await TripAPI.reorder(tripID: trip, dayID: day, stopIDs: ids, baseVersion: version)
    },
    move: { trip, stop, day, index, version throws(TripRPCError) in
      try await TripAPI.move(tripID: trip, stopID: stop, toDayID: day, toIndex: index, baseVersion: version)
    },
    remove: { trip, stop, version throws(TripRPCError) in try await TripAPI.remove(tripID: trip, stopID: stop, baseVersion: version) },
    add: { trip, day, stop, after, version throws(TripRPCError) in
      try await TripAPI.add(tripID: trip, dayID: day, stop: stop, afterStopID: after, baseVersion: version)
    }
  )
}

/// The pure half of an in-place edit: what to send for it.
nonisolated enum TripEdits {
  /// A day's stop ids with one stop moved a place up or down; nil when it is
  /// already at that end, or is not on the trip.
  static func orderAfterNudge(_ trip: Loci_Trip_TripDraft, stopID: String, up: Bool) -> (dayID: String, stopIDs: [String])? {
    for day in trip.days {
      var ids = day.stops.sorted { $0.orderIndex < $1.orderIndex }.map(\.id)
      guard let index = ids.firstIndex(of: stopID) else { continue }
      let target = up ? index - 1 : index + 1
      guard ids.indices.contains(target) else { return nil }
      ids.swapAt(index, target)
      return (day.id, ids)
    }
    return nil
  }

  /// A stop for a place added on the page. A stored place goes in by id; any
  /// other keeps its own pin and address, since the server has nothing to
  /// fill them from.
  static func stop(from place: Loci_Poi_POIDetailedInfo) -> Loci_Trip_TripStop {
    var stop = TripStopBuilder.stop(from: place, orderIndex: 0)
    if GoogleMapsRoute.hasCoordinate(place) {
      stop.latitude = place.latitude
      stop.longitude = place.longitude
    }
    let address = place.address.trimmingCharacters(in: .whitespacesAndNewlines)
    if !address.isEmpty { stop.address = address }
    return stop
  }
}

/// The trip behind a result page and the edits made to it there (web:
/// lib/itinerary/createTripView.ts). Every edit goes to TripService with the
/// version this copy was read at; the trip that comes back replaces it. An
/// edit against a trip that changed elsewhere reloads and says so rather than
/// overwriting the other change.
@Observable @MainActor final class TripEditSession {
  private(set) var trip: Loci_Trip_TripDraft?
  private(set) var isBusy = false
  /// Shown once after an edit that did not stick.
  var notice: String?

  static let conflictNotice = "This trip changed somewhere else. Showing the latest."
  static let failedNotice = "Couldn't save that change. Try again."

  @ObservationIgnored private let client: TripEditClient
  @ObservationIgnored private var loadCount = 0

  init(client: TripEditClient = .live) { self.client = client }

  /// Only the owner edits here; a co-planner suggests from the trip page.
  var canEdit: Bool {
    guard let trip else { return false }
    return !trip.hasOwner
  }

  /// Finds the trip: by its id when the page was handed one, else by the chat
  /// session. A failed refresh keeps the trip already on screen.
  func load(tripID: String?, sessionID: String?) async {
    loadCount += 1
    let mine = loadCount
    do {
      var found: Loci_Trip_TripDraft?
      if let tripID, !tripID.isEmpty {
        found = try await client.trip(tripID)
      } else if let sessionID, !sessionID.isEmpty {
        found = try await client.tripForSession(sessionID)
      }
      // A load that finishes after a newer one started must not win.
      guard mine == loadCount, let found else { return }
      trip = found
    } catch {}
  }

  func nudge(stopID: String, up: Bool) async -> Bool {
    await run { trip, client throws(TripRPCError) in
      guard let order = TripEdits.orderAfterNudge(trip, stopID: stopID, up: up) else { return nil }
      return try await client.reorder(trip.id, order.dayID, order.stopIDs, trip.version)
    }
  }

  /// To the end of another day.
  func move(stopID: String, toDayID: String) async -> Bool {
    await run { trip, client throws(TripRPCError) in
      guard let day = trip.days.first(where: { $0.id == toDayID }), !day.stops.contains(where: { $0.id == stopID }) else { return nil }
      return try await client.move(trip.id, stopID, toDayID, day.stops.count, trip.version)
    }
  }

  func remove(stopID: String) async -> Bool {
    await run { trip, client throws(TripRPCError) in try await client.remove(trip.id, stopID, trip.version) }
  }

  /// After `afterStopID` when given, else at the end of the day.
  func add(_ stop: Loci_Trip_TripStop, dayID: String, afterStopID: String? = nil) async -> Bool {
    await run { trip, client throws(TripRPCError) in try await client.add(trip.id, dayID, stop, afterStopID, trip.version) }
  }

  /// Runs one edit against the trip as it stands. Returns whether it stuck.
  private func run(
    _ edit: (Loci_Trip_TripDraft, TripEditClient) async throws(TripRPCError) -> Loci_Trip_TripDraft?
  ) async -> Bool {
    guard let current = trip, !isBusy, canEdit else { return false }
    isBusy = true
    defer { isBusy = false }
    do {
      guard var next = try await edit(current, client) else { return false }
      // Edit responses carry the trip but not who is looking at it.
      if next.viewerRole == .unspecified { next.viewerRole = current.viewerRole }
      trip = next
      return true
    } catch {
      if error.isCancelled { return false }
      if error.isVersionConflict {
        await load(tripID: current.id, sessionID: nil)
        notice = Self.conflictNotice
      } else {
        notice = Self.failedNotice
      }
      return false
    }
  }
}

/// The trip edits a result page makes in place (web: lib/api/trips.ts
/// tripEdits). Each sends the version the page read the trip at and gets the
/// trip back as it now is.
nonisolated extension TripAPI {
  /// The trip the server saved for a chat session; nil when there is none, or
  /// when the caller may not see one (signed out, an older server).
  static func tripForSession(_ sessionID: String) async throws(TripRPCError) -> Loci_Trip_TripDraft? {
    var request = Loci_Trip_GetTripForSessionRequest()
    request.sessionID = sessionID
    do {
      return try await call("Could not load the trip.", request) { await client.getTripForSession(request: $0, headers: [:]) }
    } catch {
      switch error.code {
      case .notFound, .unimplemented, .unauthenticated, .invalidArgument: return nil
      default: throw error
      }
    }
  }

  static func reorder(tripID: String, dayID: String, stopIDs: [String], baseVersion: Int64) async throws(TripRPCError) -> Loci_Trip_TripDraft {
    var request = Loci_Trip_ReorderStopsRequest()
    request.tripID = tripID
    request.dayID = dayID
    request.orderedStopIds = stopIDs
    request.baseVersion = baseVersion
    return try await call("Could not reorder.", request) { await client.reorderStops(request: $0, headers: [:]) }
  }

  static func move(tripID: String, stopID: String, toDayID: String, toIndex: Int, baseVersion: Int64) async throws(TripRPCError) -> Loci_Trip_TripDraft {
    var request = Loci_Trip_MoveStopRequest()
    request.tripID = tripID
    request.stopID = stopID
    request.toDayID = toDayID
    request.toIndex = Int32(max(toIndex, 0))
    request.baseVersion = baseVersion
    return try await call("Could not move the stop.", request) { await client.moveStop(request: $0, headers: [:]) }
  }

  static func remove(tripID: String, stopID: String, baseVersion: Int64) async throws(TripRPCError) -> Loci_Trip_TripDraft {
    var request = Loci_Trip_RemoveStopRequest()
    request.tripID = tripID
    request.stopID = stopID
    request.baseVersion = baseVersion
    return try await call("Could not remove the stop.", request) { await client.removeStop(request: $0, headers: [:]) }
  }

  /// `afterStopID` nil appends to the day.
  static func add(
    tripID: String,
    dayID: String,
    stop: Loci_Trip_TripStop,
    afterStopID: String?,
    baseVersion: Int64
  ) async throws(TripRPCError) -> Loci_Trip_TripDraft {
    var request = Loci_Trip_AddStopRequest()
    request.tripID = tripID
    request.dayID = dayID
    request.stop = stop
    if let afterStopID, !afterStopID.isEmpty { request.afterStopID = afterStopID }
    request.baseVersion = baseVersion
    return try await call("Could not add the place.", request) { await client.addStop(request: $0, headers: [:]) }
  }
}
