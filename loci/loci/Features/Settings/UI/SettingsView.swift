import SwiftUI

/// Settings, reached from Profile. One row per web settings tab
/// (loci-client/src/routes/settings/index.tsx `?tab=`), minus Billing: the
/// iOS app does not sell anything in this pass.
struct SettingsView: View {
  var body: some View {
    List {
      Section("Account") {
        NavigationLink(value: SettingsRoute.profile) { Label("Profile", systemImage: "person.crop.circle") }
        NavigationLink(value: SettingsRoute.locale) { Label("Region and units", systemImage: "globe") }
        NavigationLink(value: SettingsRoute.security) { Label("Security", systemImage: "lock.shield") }
        NavigationLink(value: SettingsRoute.data) { Label("Your data", systemImage: "tray.and.arrow.down") }
      }

      Section("Planning") {
        NavigationLink(value: SettingsRoute.travelProfiles) { Label("Travel profiles", systemImage: "suitcase") }
        NavigationLink(value: SettingsRoute.interests) { Label("Interests", systemImage: "heart.text.square") }
        NavigationLink(value: SettingsRoute.tags) { Label("Tags", systemImage: "tag") }
      }

      Section("Personalisation") {
        NavigationLink(value: SettingsRoute.personalization) { Label("Taste and privacy", systemImage: "sparkles") }
        NavigationLink(value: SettingsRoute.memory) { Label("What Loci remembers", systemImage: "brain") }
        NavigationLink(value: SettingsRoute.standingTasks) { Label("Standing tasks", systemImage: "clock.arrow.circlepath") }
      }

      Section("Connections") {
        NavigationLink(value: SettingsRoute.connections) { Label("MCP and agents", systemImage: "point.3.connected.trianglepath.dotted") }
        NavigationLink(value: SettingsRoute.calendars) { Label("Calendars", systemImage: "calendar") }
      }

      Section("App") {
        NavigationLink(value: SettingsRoute.notifications) { Label("Notifications", systemImage: "bell.badge") }
        NewsTickerToggle()
        ReviewPromptToggle()
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(Color.lociPaper.ignoresSafeArea())
    .navigationTitle("Settings")
  }
}

/// Shows a failed call's message as an alert. Bind to an optional error string.
struct ErrorAlert: ViewModifier {
  @Binding var message: String?

  func body(content: Content) -> some View {
    content.alert(
      "Something went wrong",
      isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }),
      actions: { Button("OK", role: .cancel) {} },
      message: { Text(message ?? "") }
    )
  }
}

extension View {
  func errorAlert(_ message: Binding<String?>) -> some View { modifier(ErrorAlert(message: message)) }

  /// Settings screens share the app's paper background and inset lists.
  func settingsStyle(_ title: String) -> some View {
    self.listStyle(.insetGrouped).scrollContentBackground(.hidden)
      .background(Color.lociPaper.ignoresSafeArea())
      .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
  }
}

extension Error {
  /// Text for the user: `APIError` carries its own; anything else falls back.
  var userMessage: String { (self as? LocalizedError)?.errorDescription ?? localizedDescription }
}
