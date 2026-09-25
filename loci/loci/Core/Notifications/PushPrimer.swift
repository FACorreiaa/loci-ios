import Observation
import SwiftUI

/// Asks for notifications at the moment they make sense — a search has just
/// started and will take a minute or two — and explains why before iOS's own
/// prompt, which can only be shown once. "Not now" is remembered for a week
/// so a declined ask is not repeated on every search.
@MainActor @Observable final class PushPrimer {
  static let shared = PushPrimer()
  static let snoozeInterval: TimeInterval = 7 * 24 * 60 * 60
  private static let declinedAtKey = "loci_push_primer_declined_at"

  /// Bound to the sheet in MainTabView.
  var isAsking = false
  @ObservationIgnored private var answer: CheckedContinuation<Bool, Never>?

  /// Offer the primer if iOS has never asked. Returns once the user has answered.
  func primeIfNeeded() async {
    let push = PushNotificationManager.shared
    await push.refreshAuthorizationStatus()
    guard push.authorizationStatus == .notDetermined, !isSnoozed, !isAsking else { return }

    isAsking = true
    let accepted = await withCheckedContinuation { answer = $0 }
    if accepted {
      await push.requestAuthorization()
    } else {
      UserDefaults.standard.set(Date(), forKey: Self.declinedAtKey)
    }
  }

  /// Called by the sheet's buttons, and with `false` when it is swiped away.
  func respond(_ accepted: Bool) {
    isAsking = false
    answer?.resume(returning: accepted)
    answer = nil
  }

  private var isSnoozed: Bool {
    guard let declined = UserDefaults.standard.object(forKey: Self.declinedAtKey) as? Date else { return false }
    return Date().timeIntervalSince(declined) < Self.snoozeInterval
  }
}

struct PushPrimerSheet: View {
  let primer: PushPrimer

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Image(systemName: "bell.badge")
        .font(.title2)
        .foregroundStyle(Color.lociForest)
        .accessibilityHidden(true)
      Text("Get a ping when it's ready").font(.lociTitle(22)).foregroundStyle(Color.lociInk)
      Text("Trips take a minute or two to build. We'll tell you when yours is done, even if you leave the app.")
        .font(.lociBody())
        .foregroundStyle(Color.lociMutedInk)
      Spacer(minLength: 0)
      Button { primer.respond(true) } label: {
        // Paper on forest, not the default white: dark mode's forest is a light sage.
        Text("Notify me").font(.lociBody().weight(.semibold)).foregroundStyle(Color.lociPaper).frame(maxWidth: .infinity)
      }
      .lociProminentButton()
      .controlSize(.large)
      Button { primer.respond(false) } label: {
        Text("Not now").font(.lociBody()).frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderless)
      .tint(.lociMutedInk)
    }
    .padding(24)
    .background(Color.lociPaper.ignoresSafeArea())
    .presentationDetents([.height(320)])
    .presentationDragIndicator(.visible)
  }
}
