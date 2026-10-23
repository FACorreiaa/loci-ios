import LociConnectProto
import SwiftUI

/// A shared trip's open suggestions (web: components/trip/TripProposals.tsx).
/// Everyone on the trip reacts; the owner applies or turns one down; whoever
/// suggested one can take it back. The page owns the network: each action is
/// a closure that answers with the error to show, if any.
struct TripProposalsSection: View {
  let proposals: [Loci_Chat_ActionProposal]
  let isOwner: Bool
  let currentUserID: String?
  /// The trip is loaded and confirmed by the server, so Apply has a version.
  let canApply: Bool
  let onApply: (Loci_Chat_ActionProposal) async -> String?
  let onDismiss: (Loci_Chat_ActionProposal) async -> String?
  let onReact: (Loci_Chat_ActionProposal, Int32) async -> Void

  @State private var busyID: String?
  @State private var errors: [String: String] = [:]

  var body: some View {
    Section("Suggestions · \(proposals.count)") {
      ForEach(proposals, id: \.id) { proposal in row(proposal) }
    }
  }

  private func row(_ p: Loci_Chat_ActionProposal) -> some View {
    let mine = currentUserID != nil && p.proposer.id == currentUserID
    let busy = busyID == p.id
    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 10) {
        if p.source == .editor, p.hasProposer { UserAvatar(user: p.proposer, size: 28) }
        VStack(alignment: .leading, spacing: 2) {
          Text(Self.byline(p)).font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
          Text(p.summary).font(.lociHeadline(15)).foregroundStyle(Color.lociInk)
        }
      }
      if let error = errors[p.id] {
        Text(error).font(.lociCaption(13)).foregroundStyle(Color.lociDestructive)
      }
      HStack(spacing: 8) {
        reaction(p, value: 1, count: p.upVotes, symbol: "hand.thumbsup", busy: busy)
        reaction(p, value: -1, count: p.downVotes, symbol: "hand.thumbsdown", busy: busy)
        Spacer()
        if isOwner, !Self.needsPick(p) {
          Button(busy ? "Applying…" : "Apply") { run(p) { await onApply(p) } }
            .buttonStyle(.borderedProminent).tint(.lociCoralFill).controlSize(.small)
            .disabled(busy || !canApply)
        }
        if isOwner || mine {
          Button(isOwner && !mine ? "Not now" : "Take back") { run(p) { await onDismiss(p) } }
            .controlSize(.small).disabled(busy)
        }
      }
      .buttonStyle(.borderless)
    }
    .padding(.vertical, 4)
  }

  private func reaction(_ p: Loci_Chat_ActionProposal, value: Int32, count: Int32, symbol: String, busy: Bool) -> some View {
    let on = p.myReaction == value
    return Button {
      Task { await onReact(p, on ? 0 : value) }
    } label: {
      Label("\(count)", systemImage: on ? "\(symbol).fill" : symbol).font(.lociCaption(13)).monospacedDigit()
    }
    .buttonStyle(.bordered).tint(on ? .lociCoralFill : .secondary).controlSize(.small)
    .disabled(busy)
    .accessibilityLabel(value > 0 ? "Thumbs up, \(count)" : "Thumbs down, \(count)")
    .accessibilityAddTraits(on ? .isSelected : [])
  }

  private func run(_ p: Loci_Chat_ActionProposal, _ action: @escaping @MainActor () async -> String?) {
    busyID = p.id
    errors[p.id] = nil
    Task {
      errors[p.id] = await action()
      busyID = nil
    }
  }

  static func byline(_ p: Loci_Chat_ActionProposal) -> String {
    guard p.source == .editor else { return "From the trip planner" }
    return "\(p.hasProposer ? p.proposer.shownName : "Someone") suggests"
  }

  /// A hotel search needs a pick, which happens in the planner's chat.
  static func needsPick(_ p: Loci_Chat_ActionProposal) -> Bool {
    if case .searchHotels = p.action.kind { true } else { false }
  }
}

extension TripActionError {
  /// What a failed apply means on the trip page, rather than in the chat.
  var tripPageMessage: String {
    switch kind {
    case .stale: "The trip just changed. It's reloaded: look again, then apply."
    case .gone: "This suggestion was already applied, turned down or has expired."
    case .invalid: "That stop or day is no longer on the trip. Turn this one down."
    case .other: userMessage
    }
  }
}
