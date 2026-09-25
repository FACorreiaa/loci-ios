import LociConnectProto
import SwiftUI

/// Travel ("search preference") profiles (web: TravelProfiles, settings tab "profiles").
/// ProfileService: GetUserPreferenceProfiles, Create/Update/DeleteUserPreferenceProfile,
/// SetDefaultProfile. Searches use the default profile, so a user with none
/// is sent here instead of to a search.
struct TravelProfilesView: View {
  @State private var profiles: [Loci_Profile_UserPreferenceProfile] = []
  @State private var editing: TravelProfileDraft?
  @State private var isLoading = true
  @State private var error: String?

  var body: some View {
    List {
      ForEach(profiles, id: \.id) { profile in
        Button {
          editing = TravelProfileDraft(profile)
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(profile.profileName).font(.lociHeadline()).foregroundStyle(Color.lociInk)
              if profile.isDefault { Text("Default").lociCoordStyle(10) }
            }
            Text(summary(profile)).font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
          }
        }
        .swipeActions {
          Button("Delete", role: .destructive) { Task { await delete(profile.id) } }
          if !profile.isDefault { Button("Make default") { Task { await makeDefault(profile.id) } }.tint(Color.lociForestFill) }
        }
      }
    }
    .overlay {
      if !isLoading, profiles.isEmpty {
        ContentUnavailableView {
          Label("No travel profile yet", systemImage: "suitcase")
        } description: {
          Text("Searches use your default profile. Create one to start planning.")
        } actions: {
          Button("Create a profile") { editing = TravelProfileDraft(isDefault: true) }
        }
      }
    }
    .settingsStyle("Travel profiles")
    .toolbar { Button("Add", systemImage: "plus") { editing = TravelProfileDraft(isDefault: profiles.isEmpty) } }
    .sheet(item: $editing) { draft in
      TravelProfileEditor(draft: draft) { await save($0) }
    }
    .refreshable { await load() }
    .errorAlert($error)
    .task { await load() }
  }

  private func summary(_ profile: Loci_Profile_UserPreferenceProfile) -> String {
    let budget = String(repeating: "€", count: max(Int(profile.budgetLevel), 1))
    return "\(Int(profile.searchRadiusKm)) km · \(budget) · \(profile.preferredPace.label) pace"
  }

  private func load() async {
    do {
      profiles = try await rpc("Could not load your travel profiles.") {
        await SettingsClients.profiles.getUserPreferenceProfiles(request: .init(), headers: [:])
      }.profiles
    } catch { self.error = error.userMessage }
    isLoading = false
  }

  private func save(_ draft: TravelProfileDraft) async -> Bool {
    do {
      if let id = draft.id {
        let request = draft.updateRequest(id: id)
        _ = try await rpc("Could not save the profile.", request) {
          await SettingsClients.profiles.updateUserPreferenceProfile(request: $0, headers: [:])
        }
      } else {
        let request = draft.createRequest()
        _ = try await rpc("Could not create the profile.", request) {
          await SettingsClients.profiles.createUserPreferenceProfile(request: $0, headers: [:])
        }
      }
      await load()
      return true
    } catch {
      self.error = error.userMessage
      return false
    }
  }

  private func makeDefault(_ id: String) async {
    var request = Loci_Profile_SetDefaultProfileRequest()
    request.profileID = id
    do {
      _ = try await rpc("Could not change the default.", request) { await SettingsClients.profiles.setDefaultProfile(request: $0, headers: [:]) }
      await load()
    } catch { self.error = error.userMessage }
  }

  private func delete(_ id: String) async {
    var request = Loci_Profile_DeleteUserPreferenceProfileRequest()
    request.profileID = id
    do {
      _ = try await rpc("Could not delete the profile.", request) {
        await SettingsClients.profiles.deleteUserPreferenceProfile(request: $0, headers: [:])
      }
      await load()
    } catch { self.error = error.userMessage }
  }
}

// MARK: - Enum labels

extension Loci_Profile_DayPreference {
  static let choices: [Self] = [.any, .day, .night]
  var label: String {
    switch self {
    case .day: "Daytime"
    case .night: "Evening"
    default: "Any time"
    }
  }
}

extension Loci_Profile_SearchPace {
  static let choices: [Self] = [.any, .relaxed, .moderate, .fast]
  var label: String {
    switch self {
    case .relaxed: "Relaxed"
    case .moderate: "Moderate"
    case .fast: "Fast"
    default: "Any"
    }
  }
}

extension Loci_Profile_TransportPreference {
  static let choices: [Self] = [.any, .walk, .public, .car]
  var label: String {
    switch self {
    case .walk: "Walking"
    case .public: "Public transport"
    case .car: "Car"
    default: "Any"
    }
  }
}
