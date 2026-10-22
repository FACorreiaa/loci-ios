import LociConnectProto
import SwiftUI

/// The account's notification preferences (web: settings tab "notifications").
/// UserService.GetNotificationSettings / UpdateNotificationSettings{recommendations, tripReminders, searchFinished, friendActivity, cheers, …}.
/// Search finished and Friends are the ones the server acts on: they gate the push (web and APNs) for a
/// run that ends and for friend requests and acceptances.
struct ServerNotificationSettingsSection: View {
  @State private var settings: Loci_User_NotificationSettings?
  /// Bumped per save, so only the newest reply (or failure) lands when flips overlap.
  @State private var saveGeneration = 0
  @State private var error: String?

  var body: some View {
    Section {
      if settings != nil {
        Toggle("Recommendations", isOn: binding(\.recommendations))
        Toggle("Trip reminders", isOn: binding(\.tripReminders))
        Toggle("Search finished", isOn: binding(\.searchFinished))
        Toggle("Followers and friends", isOn: binding(\.friendActivity))
        Toggle("Cheers", isOn: binding(\.cheers))
        Toggle("Achievements and leaderboard", isOn: binding(\.progressUpdates))
        Toggle("Streak reminder", isOn: binding(\.streakReminders))
        Toggle("Saved places nearby on a trip", isOn: binding(\.nearbyFits))
        Toggle("Show me on leaderboards", isOn: binding(\.leaderboardVisible))
      } else {
        ProgressView()
      }
    } header: {
      Text("Your account")
    } footer: {
      Text(
        """
        Saved to your account, so they apply on the web too. Search finished is the push you get when a search you left running ends; \
        Followers and friends, when someone follows you or asks to; Cheers, when someone cheers your achievement, city or trip \
        (at most three a day). The streak reminder comes on Sunday evening in a week you haven't explored yet. \
        Saved places nearby tells you, at most twice a day, when you pass a saved place that fits your taste on a trip day; \
        it needs location access set to Always.
        """
      )
    }
    .listRowBackground(Color.lociCard)
    .errorAlert($error)
    .task {
      do {
        let loaded = try await rpc("Could not load notification settings.") {
          await SettingsClients.user.getNotificationSettings(request: .init(), headers: [:])
        }
        settings = loaded
        StreakReminder.setEnabled(loaded.streakReminders)
        TasteFences.setEnabled(loaded.nearbyFits)
      } catch { self.error = error.userMessage }
    }
  }

  /// Flips the switch at once and sends every flag from the updated settings, so
  /// a quick second flip builds on the first rather than on stale values.
  private func binding(_ flag: WritableKeyPath<Loci_User_NotificationSettings, Bool>) -> Binding<Bool> {
    Binding(
      get: { settings?[keyPath: flag] ?? false },
      set: { newValue in
        guard let previous = settings else { return }
        var updated = previous
        updated[keyPath: flag] = newValue
        settings = updated
        saveGeneration += 1
        let generation = saveGeneration
        Task { await save(updated, generation: generation, rollback: previous) }
      }
    )
  }

  private func save(_ updated: Loci_User_NotificationSettings, generation: Int, rollback previous: Loci_User_NotificationSettings) async {
    var request = Loci_User_UpdateNotificationSettingsRequest()
    request.recommendations = updated.recommendations
    request.tripReminders = updated.tripReminders
    request.searchFinished = updated.searchFinished
    request.friendActivity = updated.friendActivity
    request.leaderboardVisible = updated.leaderboardVisible
    request.streakReminders = updated.streakReminders
    request.progressUpdates = updated.progressUpdates
    request.nearbyFits = updated.nearbyFits
    request.cheers = updated.cheers
    do {
      let saved = try await rpc("Could not save.", request) {
        await SettingsClients.user.updateNotificationSettings(request: $0, headers: [:])
      }
      guard generation == saveGeneration else { return }
      settings = saved
      StreakReminder.setEnabled(saved.streakReminders)
      TasteFences.setEnabled(saved.nearbyFits)
      if saved.nearbyFits, !previous.nearbyFits { LocationUpgrade.requestAlways() }
    } catch {
      guard generation == saveGeneration else { return }
      settings = previous
      self.error = error.userMessage
    }
  }
}
