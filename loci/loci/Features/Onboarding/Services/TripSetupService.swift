import Foundation
import LociConnectProto

/// What the wizard needs from the server, behind a protocol so the design
/// preview and the tests run without a session.
nonisolated protocol TripSetupService: Sendable {
  func catalogue() async throws -> [TripSetup.Interest]
  func profiles() async throws -> [Loci_Profile_UserPreferenceProfile]
  func create(_ request: Loci_Profile_CreateUserPreferenceProfileRequest) async throws
  func update(_ request: Loci_Profile_UpdateUserPreferenceProfileRequest) async throws
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

  func profiles() async throws -> [Loci_Profile_UserPreferenceProfile] {
    try await rpc("Could not load your travel profiles.") {
      await SettingsClients.profiles.getUserPreferenceProfiles(request: .init(), headers: [:])
    }.profiles
  }

  func create(_ request: Loci_Profile_CreateUserPreferenceProfileRequest) async throws {
    _ = try await rpc("We couldn't save your preferences.", request) {
      await SettingsClients.profiles.createUserPreferenceProfile(request: $0, headers: [:])
    }
  }

  func update(_ request: Loci_Profile_UpdateUserPreferenceProfileRequest) async throws {
    _ = try await rpc("We couldn't save your preferences.", request) {
      await SettingsClients.profiles.updateUserPreferenceProfile(request: $0, headers: [:])
    }
  }
}

/// Offline stand-in: the server's untouched "Default" profile, the curated
/// catalogue, and switches for the failure paths.
nonisolated struct PreviewTripSetupService: TripSetupService {
  var failsSave = false
  var failsCatalogue = false
  var stored: [Loci_Profile_UserPreferenceProfile] = [Self.serverDefault]

  static var serverDefault: Loci_Profile_UserPreferenceProfile {
    var profile = Loci_Profile_UserPreferenceProfile()
    profile.id = "p-default"
    profile.profileName = TripSetup.serverDefaultName
    profile.isDefault = true
    return profile
  }

  func catalogue() async throws -> [TripSetup.Interest] {
    if failsCatalogue { throw APIError.custom("Could not load interests.") }
    return TripSetup.curatedInterests.enumerated().map { TripSetup.Interest(id: "int-\($0.offset)", name: $0.element) }
  }
  func profiles() async throws -> [Loci_Profile_UserPreferenceProfile] { stored }
  func create(_ request: Loci_Profile_CreateUserPreferenceProfileRequest) async throws {
    if failsSave { throw APIError.custom("We couldn't save your preferences.") }
  }
  func update(_ request: Loci_Profile_UpdateUserPreferenceProfileRequest) async throws {
    if failsSave { throw APIError.custom("We couldn't save your preferences.") }
  }
}
