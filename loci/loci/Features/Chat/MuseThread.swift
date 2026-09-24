import Foundation
import LociConnectProto
import Observation

/// The parts of a Muse thread that are not the search turn: proactive
/// messages the server stored in the session, and the standing-task card
/// (muse-chat-contract.md, "Standing-task card").
///
/// Card flow: a follow-up that reads like a standing request goes to
/// ProposeWatch instead of a new search; the card shows what the server
/// understood. Confirm → CreateWatch, whose confirmation message (already
/// stored server side) is appended here. Not now → nothing is called.
@MainActor @Observable final class MuseThread {
  enum Card: Equatable {
    /// ProposeWatch is running.
    case proposing
    case proposal(Loci_Chat_WatchProposal)
    /// CreateWatch is running for this proposal.
    case confirming(Loci_Chat_WatchProposal)
    /// A call failed. `proposal` is kept when there is one, so Confirm can be tried again.
    case failed(WatchError, proposal: Loci_Chat_WatchProposal?)
  }

  /// Messages after the search turn, oldest first.
  private(set) var messages: [MuseMessage] = []
  /// What the user asked for while a card is up; drawn as the user bubble above it.
  private(set) var request: String?
  private(set) var card: Card?
  /// The newest watch confirmed from this thread's card, so the page can scroll to its confirmation.
  private(set) var confirmedWatchId: String?

  private let service: StandingTaskService
  private let timezone: String

  init(service: StandingTaskService = ConnectStandingTaskService(), timezone: String = TimeZone.current.identifier) {
    self.service = service
    self.timezone = timezone
  }

  /// Proactive messages stored in the session. Failing quietly: the search
  /// turn is still the page, and these show up on the next open.
  func loadHistory(sessionId: String) async {
    guard let history = try? await service.history(sessionId: sessionId) else { return }
    let stored = MuseMessage.proactive(in: history)
    let storedIds = Set(stored.map(\.id))
    // Keep what was added locally this visit unless the server already has it.
    messages = stored + messages.filter { !storedIds.contains($0.id) }
  }

  /// The id of the message a push named, as this thread spells it; nil when it
  /// is not here (not stored yet, or not a proactive message).
  func messageId(matching id: String) -> String? {
    messages.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }?.id
  }

  /// A follow-up that reads like a standing request: ask the server what it understood.
  func offer(_ text: String) async {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !isBusy else { return }
    request = trimmed
    card = .proposing
    do throws(WatchError) {
      let proposal = try await service.propose(text: trimmed, timezone: timezone)
      guard request == trimmed else { return }
      card = .proposal(proposal)
    } catch {
      guard request == trimmed else { return }
      card = .failed(error, proposal: nil)
    }
  }

  /// Confirm: store the watch against this thread and show the agent's confirmation.
  func confirm(sessionId: String) async {
    guard let proposal = card?.proposal, !isBusy else { return }
    card = .confirming(proposal)
    do throws(WatchError) {
      let response = try await service.create(sessionId: sessionId, proposal: proposal)
      if let request { messages.append(MuseMessage(id: "request-\(response.watch.id)", role: .user, text: request)) }
      if response.hasConfirmation { messages.append(MuseMessage(response.confirmation)) }
      request = nil
      card = nil
      confirmedWatchId = response.watch.id
    } catch {
      card = .failed(error, proposal: proposal)
    }
  }

  /// Not now, or dismissing a failure: the card and its request go, nothing is called.
  func dismiss() {
    request = nil
    card = nil
  }

  private var isBusy: Bool {
    switch card {
    case .proposing, .confirming: true
    default: false
    }
  }
}

extension MuseThread.Card {
  /// The proposal on the card, if it has one.
  var proposal: Loci_Chat_WatchProposal? {
    switch self {
    case .proposal(let proposal), .confirming(let proposal): proposal
    case .failed(_, let proposal): proposal
    case .proposing: nil
    }
  }
}

extension MuseThread {
  /// A thread in a fixed state for `-designPreview` screenshots.
  static func preview(messages: [MuseMessage] = [], request: String? = nil, card: Card? = nil) -> MuseThread {
    let thread = MuseThread(service: PreviewStandingTaskService())
    thread.messages = messages
    thread.request = request
    thread.card = card
    return thread
  }
}
