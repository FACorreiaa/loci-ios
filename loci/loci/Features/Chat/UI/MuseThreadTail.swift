import LociConnectProto
import SwiftUI

/// Everything a Muse thread shows after the search turn: proactive messages,
/// then the standing-task card with the request that raised it.
struct MuseThreadTail: View {
  let thread: MuseThread
  /// The session the card's Confirm attaches the task to; no card without one.
  let sessionId: String?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var arrival: AnyTransition { reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(thread.messages) { message in
        MuseMessageView(message: message).id(message.id).transition(arrival)
      }
      if let request = thread.request, let card = thread.card {
        MuseBubble(role: .user) { Text(request) }
        StandingTaskCard(
          card: card,
          onConfirm: { Task { if let sessionId { await thread.confirm(sessionId: sessionId) } } },
          onNotNow: { thread.dismiss() }
        )
        .transition(arrival)
      }
    }
    .animation(reduceMotion ? LociTheme.reducedFade : LociTheme.resultArrive, value: thread.messages)
    .animation(reduceMotion ? LociTheme.reducedFade : LociTheme.resultArrive, value: thread.card)
  }
}

/// One stored message as a bubble, with the proactive caption above an agent's own message.
struct MuseMessageView: View {
  let message: MuseMessage

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let caption = message.caption {
        MuseCaption(text: caption)
      }
      MuseBubble(role: message.role == .user ? .user : .agent) { Text(Self.markdown(message.text)) }
    }
    .accessibilityElement(children: .combine)
  }

  /// Bold, links and the like inside the bubble; plain text when it does not parse.
  static func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
  }
}

/// The 11pt uppercase line above a proactive bubble: "Standing task", "Briefing · 07:00".
struct MuseCaption: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.lociCoord(11))
      .textCase(.uppercase)
      .tracking(1.2)
      .foregroundStyle(Color.museTextSecondary)
      .padding(.horizontal, 4)
  }
}

/// The standing-task card: agent-bubble styled, what the server understood,
/// and Confirm / Not now.
struct StandingTaskCard: View {
  let card: MuseThread.Card
  var onConfirm: () -> Void = {}
  var onNotNow: () -> Void = {}

  var body: some View {
    // No caption: the card is a question, not something the agent posted on its own.
    MuseBubble(role: .agent) {
      VStack(alignment: .leading, spacing: 10) {
        content
      }
    }
  }

  @ViewBuilder private var content: some View {
    switch card {
    case .proposing:
      HStack(spacing: 10) {
        ProgressView()
        Text("Working out the schedule…").foregroundStyle(Color.museTextSecondary)
      }
      .accessibilityElement(children: .combine)
    case .proposal(let proposal):
      details(proposal)
      buttons(confirm: "Confirm", busy: false)
    case .confirming(let proposal):
      details(proposal)
      buttons(confirm: "Confirm", busy: true)
    case let .failed(error, proposal):
      if let proposal { details(proposal) }
      Label(error.errorDescription ?? "", systemImage: "exclamationmark.circle")
        .font(.lociBody(15))
        .foregroundStyle(Color.museText)
      if proposal != nil, error == .offline || error == .other {
        buttons(confirm: "Try again", busy: false)
      } else {
        Button("Not now", action: onNotNow).buttonStyle(MusePillButtonStyle())
      }
    }
  }

  private func details(_ proposal: Loci_Chat_WatchProposal) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(proposal.title)
        .font(.lociHeadline(17).weight(.semibold))
        .foregroundStyle(Color.museText)
      Label(proposal.scheduleHuman, systemImage: "clock")
        .font(.museStatus)
        .foregroundStyle(Color.museTextSecondary)
      Text(proposal.spec)
        .font(.lociBody(15))
        .foregroundStyle(Color.museText)
        .lineLimit(4)
    }
    .accessibilityElement(children: .combine)
  }

  private func buttons(confirm: String, busy: Bool) -> some View {
    HStack(spacing: 8) {
      Button(action: onConfirm) {
        if busy { ProgressView().tint(Color.lociPaper) } else { Text(confirm) }
      }
      .buttonStyle(MuseConfirmButtonStyle())
      .disabled(busy)
      .accessibilityLabel(busy ? "Saving the standing task" : confirm)
      Button("Not now", action: onNotNow)
        .buttonStyle(MusePillButtonStyle())
        .disabled(busy)
    }
    .padding(.top, 4)
  }
}

/// The card's primary action: the composer's Send colours on a pill.
private struct MuseConfirmButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.museName)
      .foregroundStyle(Color.lociPaper)
      .padding(.horizontal, 18)
      .frame(minWidth: 96, minHeight: LociTheme.Muse.headerButtonSize)
      .background(Color.lociForest, in: Capsule())
      .contentShape(Capsule())
      .opacity(configuration.isPressed ? 0.7 : isEnabled ? 1 : 0.8)
  }
}
