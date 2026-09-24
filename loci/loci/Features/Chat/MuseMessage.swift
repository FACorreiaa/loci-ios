import Foundation
import LociConnectProto
import SwiftProtobuf

/// One message in a Muse thread beyond the search turn itself: something the
/// agent posted on its own (a standing task running, a briefing) or a turn
/// shown locally around a standing-task card.
///
/// muse-chat-contract.md, "Proactive messages": the same agent bubble with an
/// 11pt uppercase caption above it, taken from the message's `source_label`.
nonisolated struct MuseMessage: Equatable, Identifiable, Sendable {
  enum Role: Equatable, Sendable { case user, agent }
  enum Origin: Equatable, Sendable { case reply, proactive }

  let id: String
  let role: Role
  let text: String
  let origin: Origin
  /// The server's caption, e.g. "Standing task" or "Briefing · 07:00". Empty for replies.
  let sourceLabel: String
  let timestamp: Date?

  init(id: String, role: Role, text: String, origin: Origin = .reply, sourceLabel: String = "", timestamp: Date? = nil) {
    self.id = id
    self.role = role
    self.text = text
    self.origin = origin
    self.sourceLabel = sourceLabel
    self.timestamp = timestamp
  }

  /// A stored message. UNSPECIFIED (anything saved before the field existed)
  /// and values this build does not know read as a reply.
  init(_ message: Loci_Chat_ConversationMessage) {
    self.init(
      id: message.id,
      role: message.role == .user ? .user : .agent,
      text: message.content,
      origin: message.origin == .proactive ? .proactive : .reply,
      sourceLabel: message.sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines),
      timestamp: message.hasTimestamp ? message.timestamp.date : nil
    )
  }

  /// The caption above a proactive bubble; nil for replies. A proactive message
  /// the server sent without a label still gets one, so it never looks like an answer.
  var caption: String? {
    guard origin == .proactive else { return nil }
    return sourceLabel.isEmpty ? Self.fallbackCaption : sourceLabel
  }

  static let fallbackCaption = "From Loci"

  /// The agent's own messages in a stored thread, oldest first. Replies are
  /// already drawn by the search turn, so only proactive ones are added.
  static func proactive(in history: [Loci_Chat_ConversationMessage]) -> [MuseMessage] {
    history.map(MuseMessage.init).filter { $0.origin == .proactive && $0.role == .agent && !$0.text.isEmpty }
      .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
  }
}
