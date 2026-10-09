import SwiftUI

/// A page under Profile › Settings.
enum SettingsRoute: Hashable {
  case profile, locale, security, data, travelProfiles, interests, tags, personalization, memory, standingTasks, connections, calendars
  case notifications, changePassword, changeEmail
  case setupInstructions(clientKind: String)
}

struct SettingsRouteDestination: View {
  let route: SettingsRoute

  var body: some View {
    switch route {
    case .profile: AccountProfileView()
    case .locale: LocaleSettingsView()
    case .security: SecuritySettingsView()
    case .data: AccountDataView()
    case .travelProfiles: TravelProfilesView()
    case .interests: InterestsSettingsView()
    case .tags: TagsSettingsView()
    case .personalization: PersonalizationSettingsView()
    case .memory: MemoryView()
    case .standingTasks: StandingTasksView()
    case .connections: ConnectionsView()
    case .calendars: CalendarConnectionsView()
    case .notifications: NotificationSettingsView()
    case .changePassword: ChangePasswordView()
    case .changeEmail: ChangeEmailView()
    case .setupInstructions(let clientKind): SetupInstructionsView(clientKind: clientKind)
    }
  }
}
