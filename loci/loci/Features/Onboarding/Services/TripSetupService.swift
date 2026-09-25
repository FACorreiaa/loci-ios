import Foundation
import LociConnectProto

/// What the wizard needs from the server, behind a protocol so the design
/// preview and the tests run without a session.
nonisolated protocol TripSetupService: Sendable {
  func catalogue() async throws -> [TripSetup.Interest]
  func profileCount() async throws -> Int
  func create(_ request: Loci_Profile_CreateUserPreferenceProfileRequest) async throws
}

nonisolated struct ConnectTripSetupService: TripSetupService {
  func catalogue() async throws -> [TripSetup.Interest] {
    var request = Loci_Interest_GetInterestsRequest()
    request.activeOnly = true
    let response = try await rpc("Could not load interests.", request) {
      await SettingsClients.interests.getInterests(request: $0, headers: [:])
    }
    return response.interests.filter(\.active).map { TripSetup.Interest(id: $0.id, name: $0.name) }
  }

  func profileCount() async throws -> Int {
    try await rpc("Could not load your travel profiles.") {
      await SettingsClients.profiles.getUserPreferenceProfiles(request: .init(), headers: [:])
    }.profiles.count
  }

  func create(_ request: Loci_Profile_CreateUserPreferenceProfileRequest) async throws {
    _ = try await rpc("We couldn't save your preferences.", request) {
      await SettingsClients.profiles.createUserPreferenceProfile(request: $0, headers: [:])
    }
  }
}

nonisolated struct PreviewTripSetupService: TripSetupService {
  var fails = false

  func catalogue() async throws -> [TripSetup.Interest] {
    TripSetup.curatedInterests.enumerated().map { TripSetup.Interest(id: "int-\($0.offset)", name: $0.element) }
  }
  func profileCount() async throws -> Int { 0 }
  func create(_ request: Loci_Profile_CreateUserPreferenceProfileRequest) async throws {
    if fails { throw APIError.custom("We couldn't save your preferences.") }
  }
}
