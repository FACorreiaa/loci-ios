import Foundation
import Observation
import UserNotifications

/// A place waiting for its "How was it?".
nonisolated struct PendingRating: Codable, Equatable, Sendable {
  let poiID: String
  let name: String
  let cityName: String
  let category: String
  let arrivedAt: Date
  var dueAt: Date
}

/// The places to ask "How was it?" about, and when.
///
/// An arrival is not the moment to ask: the traveller has only just got there.
/// A place becomes due 45 minutes after arriving, when they set off for the next
/// stop, or at once when they tap "I've been here". A local notification at the
/// due time asks too, so a backgrounded app still gets an answer; its action
/// buttons record the verdict without opening the app.
///
/// The queue is persisted, so a notification tapped after the app was killed
/// still finds its place.
@MainActor @Observable final class RatePrompter {
  static let shared = RatePrompter()

  static let followUp: TimeInterval = 45 * 60
  static let capacity = 10
  static let maxAge: TimeInterval = 3 * 24 * 60 * 60

  private static let key = "pendingRatings"

  private(set) var queue: [PendingRating] = []
  /// Bumped by `refresh()` so views re-read `current` as time passes.
  private(set) var clock: Date

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let live: Bool
  @ObservationIgnored private let now: () -> Date

  init(defaults: UserDefaults = .standard, live: Bool = true, now: @escaping () -> Date = Date.init) {
    self.defaults = defaults
    self.live = live
    self.now = now
    self.clock = now()
    if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode([PendingRating].self, from: data) {
      queue = saved
    }
    prune()
  }

  /// The place to ask about now: the one that has been due longest.
  var current: PendingRating? {
    queue.filter { $0.dueAt <= clock }.min { $0.dueAt < $1.dueAt }
  }

  /// A place reached on a walk. Only server places can be ranked, and only
  /// against a city.
  func enqueueArrival(poiID: String, name: String, cityName: String, category: String) {
    let city = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard UUID(uuidString: poiID) != nil, !city.isEmpty else { return }
    let at = now()
    enqueue(PendingRating(poiID: poiID, name: name, cityName: city, category: category, arrivedAt: at, dueAt: at.addingTimeInterval(Self.followUp)))
  }

  func enqueue(_ rating: PendingRating) {
    queue.removeAll { $0.poiID == rating.poiID }
    queue.append(rating)
    if queue.count > Self.capacity {
      queue = Array(queue.sorted { $0.arrivedAt > $1.arrivedAt }.prefix(Self.capacity))
    }
    clock = now()
    save()
    if live, rating.dueAt > clock { Task { await RateReminder.schedule(rating) } }
  }

  /// Ask about this place now, e.g. when the traveller walks on.
  func markDue(poiID: String) {
    guard let index = queue.firstIndex(where: { $0.poiID == poiID }) else { return }
    clock = now()
    queue[index].dueAt = min(queue[index].dueAt, clock)
    save()
    if live { RateReminder.cancel(poiID: poiID) }
  }

  /// The traveller answered or dismissed it.
  func resolve(poiID: String) {
    queue.removeAll { $0.poiID == poiID }
    save()
    if live { RateReminder.cancel(poiID: poiID) }
  }

  func refresh() {
    clock = now()
    prune()
  }

  func pending(poiID: String) -> PendingRating? { queue.first { $0.poiID == poiID } }

  private func prune() {
    let cutoff = now().addingTimeInterval(-Self.maxAge)
    let kept = queue.filter { $0.arrivedAt > cutoff }
    if kept.count != queue.count {
      queue = kept
      save()
    }
  }

  private func save() {
    if let data = try? JSONEncoder().encode(queue) { defaults.set(data, forKey: Self.key) }
  }
}

/// The local notification that asks "How was it?" when the app is not in front.
nonisolated enum RateReminder {
  static func identifier(_ poiID: String) -> String { "rate-\(poiID)" }

  static func schedule(_ rating: PendingRating) async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
    let content = UNMutableNotificationContent()
    content.title = HowWasItCopy.prompt(rating.name)
    content.body = "One tap puts it in your \(rating.cityName) list."
    content.categoryIdentifier = NotificationCategory.lociRate
    content.threadIdentifier = "rate"
    content.userInfo = ["poiID": rating.poiID]
    let wait = max(1, rating.dueAt.timeIntervalSinceNow)
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
    try? await center.add(UNNotificationRequest(identifier: identifier(rating.poiID), content: content, trigger: trigger))
  }

  static func cancel(poiID: String) {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(poiID)])
  }

  /// A notification answered: a verdict button records it straight away; a
  /// plain tap brings the card up. The place leaves the queue only once the
  /// server has it placed. When comparisons remain (they can't be asked on the
  /// lock screen), or the call fails, it stays due, and the card asks again
  /// when the app opens; the same verdict resumes where it stopped.
  @MainActor static func handle(
    actionIdentifier: String,
    poiID: String,
    prompter: RatePrompter = .shared,
    service: any RankingService = ConnectRankingService()
  ) async {
    guard let rating = prompter.pending(poiID: poiID) else { return }
    guard let verdict = RankingVerdict(actionIdentifier: actionIdentifier) else {
      prompter.markDue(poiID: poiID)
      return
    }
    do {
      let step = try await service.rate(rating, verdict: verdict)
      if step.next == nil {
        prompter.resolve(poiID: poiID)
      } else {
        prompter.markDue(poiID: poiID)
      }
    } catch {
      prompter.markDue(poiID: poiID)
    }
  }
}
