import LociConnectProto
import SwiftUI

/// The account profile form (web: settings tab "settings", profile card).
/// UserService.GetUserProfile → UpdateUserProfile{params}.
struct AccountProfileView: View {
  @State private var original = Loci_User_UserProfile()
  @State private var draft = ProfileDraft()
  @State private var isLoading = true
  @State private var isSaving = false
  @State private var error: String?
  @State private var saved = false

  var body: some View {
    Form {
      Section("Name") {
        TextField("Display name", text: $draft.displayName).textContentType(.name)
        TextField("First name", text: $draft.firstname).textContentType(.givenName)
        TextField("Last name", text: $draft.lastname).textContentType(.familyName)
        TextField("Username", text: $draft.username).textContentType(.username).textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      }
      Section("Contact") {
        LabeledContent("Email", value: original.email)
        TextField("Phone (+351…)", text: $draft.phoneNumber).textContentType(.telephoneNumber).keyboardType(.phonePad)
      }
      Section("Home") {
        TextField("City", text: $draft.city).textContentType(.addressCity)
        TextField("Country", text: $draft.country).textContentType(.countryName)
      }
      Section("About you") {
        TextField("A line or two for your travel companions", text: $draft.aboutYou, axis: .vertical).lineLimit(3...6)
      }
      if saved { Text("Saved.").foregroundStyle(Color.lociForest) }
    }
    .disabled(isLoading)
    .overlay { if isLoading { ProgressView() } }
    .settingsStyle("Profile")
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") { Task { await save() } }.disabled(isSaving || draft == ProfileDraft(original))
      }
    }
    .errorAlert($error)
    .task { await load() }
  }

  private func load() async {
    do {
      let response = try await rpc("Could not load your profile.") {
        await SettingsClients.user.getUserProfile(request: .init(), headers: [:])
      }
      original = response.profile
      draft = ProfileDraft(response.profile)
    } catch { self.error = error.userMessage }
    isLoading = false
  }

  private func save() async {
    isSaving = true
    defer { isSaving = false }
    var request = Loci_User_UpdateUserProfileRequest()
    request.params = draft.changes(from: ProfileDraft(original))
    do {
      _ = try await rpc("Could not save your profile.", request) { await SettingsClients.user.updateUserProfile(request: $0, headers: [:]) }
      await load()
      saved = true
    } catch { self.error = error.userMessage }
  }
}

/// Editable copy of the profile fields the form shows.
struct ProfileDraft: Equatable {
  var displayName = ""
  var firstname = ""
  var lastname = ""
  var username = ""
  var phoneNumber = ""
  var city = ""
  var country = ""
  var aboutYou = ""

  init() {}

  init(_ profile: Loci_User_UserProfile) {
    displayName = profile.displayName
    firstname = profile.firstname
    lastname = profile.lastname
    username = profile.username
    phoneNumber = profile.phoneNumber
    city = profile.city
    country = profile.country
    aboutYou = profile.aboutYou
  }

  /// Only the fields that changed and are non-empty. Every field in
  /// UpdateProfileParams is `optional` with `min_len: 1`, so an empty string
  /// would be sent as present and rejected (web: `buildUpdateProfileParams`).
  func changes(from old: ProfileDraft) -> Loci_User_UpdateProfileParams {
    var params = Loci_User_UpdateProfileParams()
    func set(_ new: String, _ previous: String, _ apply: (String) -> Void) {
      let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty, trimmed != previous { apply(trimmed) }
    }
    set(displayName, old.displayName) { params.displayName = $0 }
    set(firstname, old.firstname) { params.firstname = $0 }
    set(lastname, old.lastname) { params.lastname = $0 }
    set(username, old.username) { params.username = $0 }
    set(phoneNumber, old.phoneNumber) { params.phoneNumber = $0 }
    set(city, old.city) { params.city = $0 }
    set(country, old.country) { params.country = $0 }
    set(aboutYou, old.aboutYou) { params.aboutYou = $0 }
    return params
  }
}
