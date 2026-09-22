import SwiftUI

/// Settings, reached from Profile. One row per web settings tab
/// (loci-client/src/routes/settings/index.tsx `?tab=`), minus Billing: the
/// iOS app does not sell anything in this pass.
struct SettingsView: View {
  var body: some View {
    List {
      Section("Account") {
        NavigationLink { AccountProfileView() } label: { Label("Profile", systemImage: "person.crop.circle") }
        NavigationLink { LocaleSettingsView() } label: { Label("Region and units", systemImage: "globe") }
        NavigationLink { SecuritySettingsView() } label: { Label("Security", systemImage: "lock.shield") }
        NavigationLink { AccountDataView() } label: { Label("Your data", systemImage: "tray.and.arrow.down") }
      }

      Section("Planning") {
        NavigationLink { TravelProfilesView() } label: { Label("Travel profiles", systemImage: "suitcase") }
        NavigationLink { InterestsSettingsView() } label: { Label("Interests", systemImage: "heart.text.square") }
        NavigationLink { TagsSettingsView() } label: { Label("Tags", systemImage: "tag") }
      }

      Section("Personalisation") {
        NavigationLink { PersonalizationSettingsView() } label: { Label("Taste and privacy", systemImage: "sparkles") }
        NavigationLink { MemoryView() } label: { Label("What Loci remembers", systemImage: "brain") }
      }

      Section("Connections") {
        NavigationLink { ConnectionsView() } label: { Label("MCP and agents", systemImage: "point.3.connected.trianglepath.dotted") }
        NavigationLink { CalendarConnectionsView() } label: { Label("Calendars", systemImage: "calendar") }
      }

      Section("App") {
        NavigationLink { NotificationSettingsView() } label: { Label("Notifications", systemImage: "bell.badge") }
        NewsTickerToggle()
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
