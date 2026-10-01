import CoreLocation
import Foundation
import LociConnectProto
import SwiftProtobuf

/// GamificationService (loci.gamification) plus the two RPCs points ride on
/// elsewhere: TravelHistoryService.RecordVisit with a device fix, and
/// CustomAuthService's phone and Facebook links. Web: lib/api/gamification.ts.
nonisolated enum ProgressAPI {
  private static let client = Loci_Gamification_GamificationServiceClient(client: ConnectTransport.shared.protocolClient)
  private static let history = Loci_Travelhistory_TravelHistoryServiceClient(client: ConnectTransport.shared.protocolClient)
  static let auth = Loci_CustomAuth_CustomAuthServiceClient(client: ConnectTransport.shared.protocolClient)

  /// The device's zone, which decides the local day for streaks and caps.
  static var timezone: String { TimeZone.current.identifier }

  static func progress() async throws -> Loci_Gamification_Progress {
    try await rpc("Could not load your progress.", Loci_Gamification_GetMyProgressRequest()) {
      await client.getMyProgress(request: $0, headers: [:])
    }.progress
  }

  static func checkIn() async throws -> Loci_Gamification_DailyCheckInResponse {
    var request = Loci_Gamification_DailyCheckInRequest()
    request.timezone = timezone
    return try await rpc("Could not check in.", request) { await client.dailyCheckIn(request: $0, headers: [:]) }
  }

  static func leaderboard(period: Loci_Gamification_LeaderboardPeriod, metric: Loci_Gamification_LeaderboardMetric) async throws
    -> Loci_Gamification_GetLeaderboardResponse
  {
    var request = Loci_Gamification_GetLeaderboardRequest()
    request.period = period
    request.metric = metric
    return try await rpc("Could not load the leaderboard.", request) { await client.getLeaderboard(request: $0, headers: [:]) }
  }

  static func history(pageToken: String = "") async throws -> Loci_Gamification_ListPointsHistoryResponse {
    var request = Loci_Gamification_ListPointsHistoryRequest()
    request.pageSize = 30
    request.pageToken = pageToken
    return try await rpc("Could not load your points.", request) { await client.listPointsHistory(request: $0, headers: [:]) }
  }

  static func completeTripDay(tripID: String, dayID: String, stopsDone: Int) async throws -> Loci_Gamification_CompleteTripDayResponse {
    var request = Loci_Gamification_CompleteTripDayRequest()
    request.tripID = tripID
    request.dayID = dayID
    request.stopsDone = Int32(stopsDone)
    request.timezone = timezone
    return try await rpc("Could not save the day.", request) { await client.completeTripDay(request: $0, headers: [:]) }
  }

  /// Records a place reached on the spot, with where the phone was, so the
  /// server can score it. Returns the points it earned.
  static func recordVisit(_ visit: SpotVisit, at location: CLLocation) async throws -> Int {
    var request = Loci_Travelhistory_RecordVisitRequest()
    request.cityName = visit.cityName
    request.latitude = visit.latitude
    request.longitude = visit.longitude
    if !visit.poiID.isEmpty { request.poiID = visit.poiID }
    if !visit.poiName.isEmpty { request.poiName = visit.poiName }
    request.visitedAt = Google_Protobuf_Timestamp(date: location.timestamp)
    var fix = Loci_Travelhistory_DeviceFix()
    fix.latitude = location.coordinate.latitude
    fix.longitude = location.coordinate.longitude
    fix.accuracyM = max(location.horizontalAccuracy, 0)
    fix.observedAt = Google_Protobuf_Timestamp(date: location.timestamp)
    request.deviceLocation = fix
    return Int(try await rpc("Could not record the visit.", request) { await history.recordVisit(request: $0, headers: [:]) }.pointsAwarded)
  }

  // MARK: Being found by friends

  static func sendPhoneCode(to phone: String) async throws {
    var request = Loci_CustomAuth_SendPhoneVerificationRequest()
    request.phoneNumber = phone
    _ = try await rpc("Could not send the code.", request) { await auth.sendPhoneVerification(request: $0, headers: [:]) }
  }

  static func attachPhone(_ phone: String, code: String) async throws {
    var request = Loci_CustomAuth_AttachVerifiedPhoneRequest()
    request.phoneNumber = phone
    request.code = code
    _ = try await rpc("Could not verify the number.", request) { await auth.attachVerifiedPhone(request: $0, headers: [:]) }
  }
}

/// A place reached on the spot: by Near me's walking directions or a trip
/// day's arrival fence.
nonisolated struct SpotVisit: Sendable, Equatable {
  var poiID: String
  var poiName: String
  var cityName: String
  var latitude: Double
  var longitude: Double
}

extension SpotVisit {
  init(_ place: Loci_Poi_POIDetailedInfo) {
    self.init(poiID: place.id, poiName: place.name, cityName: place.city, latitude: place.latitude, longitude: place.longitude)
  }
}
