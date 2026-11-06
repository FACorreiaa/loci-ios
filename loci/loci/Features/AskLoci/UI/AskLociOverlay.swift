import SwiftUI

/// Ask Loci over whatever is on screen: talk or type, read or hear the answer.
struct AskLociOverlay: View {
  var controller = AskLociController.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Backdrop left showing above the panel: somewhere to tap to close.
  private static let backdropGap: CGFloat = 64

  var body: some View {
    // The space between the safe areas, keyboard included: the panel is sized
    // to what is left above the keyboard, so its header (and Close) stays on screen.
    GeometryReader { proxy in
      ZStack(alignment: .bottom) {
        if controller.isOpen {
          Color.black.opacity(0.4)
            .ignoresSafeArea()
            .onTapGesture { controller.close() }
            .accessibilityHidden(true)
            .transition(.opacity)
          AskLociPanel(controller: controller, available: proxy.size.height, backdropGap: Self.backdropGap)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
    }
    .animation(reduceMotion ? LociTheme.reducedFade : LociTheme.defaultSpring, value: controller.isOpen)
  }
}

private struct AskLociPanel: View {
  let controller: AskLociController
  /// Height between the safe areas, keyboard included.
  let available: CGFloat
  let backdropGap: CGFloat

  private static let maxWidth: CGFloat = 560
  private static let answerHeightShare: CGFloat = 0.72

  var body: some View {
    VStack(spacing: 0) {
      // The header and composer keep their height; the answers give way and scroll.
      AskLociHeader(controller: controller)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
      if controller.turns.isEmpty {
        Text("Ask about your trips, your lists, or anywhere you're going.")
          .font(.museBody)
          .foregroundStyle(Color.museTextSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, LociTheme.defaultPadding)
          .padding(.vertical, 12)
      } else {
        AskLociAnswers(controller: controller)
          .frame(maxHeight: max(available * Self.answerHeightShare, 0))
      }
      AskLociComposer(controller: controller)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
    }
    .background {
      // Down to the screen's edge, and behind the keyboard when it is up.
      UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
        .fill(Color.museCanvas)
        .ignoresSafeArea(edges: .bottom)
    }
    .frame(maxWidth: Self.maxWidth)
    // A cap, applied after the fill so a short panel stays short.
    .frame(maxHeight: max(available - backdropGap, 0), alignment: .bottom)
    .accessibilityAddTraits(.isModal)
    .accessibilityAction(.escape) { controller.close() }
  }
}

private struct AskLociHeader: View {
  @Bindable var controller: AskLociController

  var body: some View {
    HStack(spacing: 4) {
      Text("Ask Loci")
        .font(.museName.weight(.semibold))
        .foregroundStyle(Color.museText)
        .accessibilityAddTraits(.isHeader)
      Spacer()
      Button {
        controller.speakTyped.toggle()
      } label: {
        Image(systemName: controller.speakTyped ? "speaker.wave.2.fill" : "speaker.slash")
          .frame(width: LociTheme.minTapTarget, height: LociTheme.minTapTarget)
      }
      .accessibilityLabel(controller.speakTyped ? "Stop reading answers aloud" : "Read answers aloud")
      Button {
        controller.close()
      } label: {
        Image(systemName: "xmark")
          .frame(width: LociTheme.minTapTarget, height: LociTheme.minTapTarget)
      }
      .accessibilityLabel("Close")
    }
    .foregroundStyle(Color.museText)
    .padding(.leading, LociTheme.defaultPadding)
    .padding(.trailing, 8)
    .padding(.top, 8)
  }
}

private struct AskLociAnswers: View {
  let controller: AskLociController
  @State private var scroll = ScrollPosition(edge: .bottom)
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 12) {
        ForEach(controller.turns) { turn in
          AskLociTurnView(turn: turn, controller: controller)
        }
      }
      .padding(.horizontal, LociTheme.defaultPadding)
      .padding(.vertical, 8)
    }
    .defaultScrollAnchor(.bottom)
    .scrollPosition($scroll)
    // A new question goes under the rest: bring it into view, wherever the list was.
    .onChange(of: controller.turns.count) { old, new in
      if new > old { withAnimation(reduceMotion ? nil : LociTheme.resultArrive) { scroll.scrollTo(edge: .bottom) } }
    }
    .scrollDismissesKeyboard(.interactively)
  }
}

private struct AskLociTurnView: View {
  let turn: AskLociTurn
  let controller: AskLociController

  var body: some View {
    VStack(spacing: 8) {
      MuseBubble(role: .user) { Text(verbatim: turn.you) }
      if !turn.reply.isEmpty {
        MuseBubble(role: .agent) { Text(verbatim: turn.reply).textSelection(.enabled) }
      }
      if let status = turn.status ?? (!turn.done && turn.reply.isEmpty ? "Thinking…" : nil) {
        Text(verbatim: status)
          .font(.museStatus)
          .foregroundStyle(Color.museTextSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      ForEach(turn.cards) { card in
        AskLociCardView(card: card, turnID: turn.id, controller: controller)
      }
      if let note = turn.closingNote {
        Text(verbatim: note)
          .font(.lociCaption(13))
          .foregroundStyle(Color.museTextSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if turn.offerChat {
        Button("Open the chat") {
          controller.close()
          AppRouter.shared.selectedTab = .assistant
        }
        .buttonStyle(MusePillButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

private struct AskLociComposer: View {
  let controller: AskLociController
  @State private var text = ""

  private var micState: DictationController.State { controller.micState }
  private var canSend: Bool {
    micState == .idle && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  private var hint: String? {
    switch micState {
    case .recording: "Listening. Stops when you do, or tap the mic."
    case .transcribing: "Working out what you said…"
    case .idle: controller.dictation.error
    }
  }

  var body: some View {
    VStack(spacing: 6) {
      if let hint {
        Text(verbatim: hint)
          .font(.museStatus)
          .foregroundStyle(Color.museTextSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityAddTraits(.updatesFrequently)
      }
      HStack(alignment: .bottom, spacing: 8) {
        TextField("Ask anything", text: $text, axis: .vertical)
          .lineLimit(1...4)
          .font(.museBody)
          .foregroundStyle(Color.museText)
          .submitLabel(.send)
          .onSubmit(send)
          // A multi-line field takes Return as a new line, not a submit: a
          // Return typed at the end sends, as the key's "send" label says.
          .onChange(of: text) { old, new in
            guard new.hasSuffix("\n"), !old.hasSuffix("\n") else { return }
            text = String(new.dropLast())
            send()
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(Color.museAgentBubble, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        if !controller.dictation.isUnavailable {
          AskLociRoundButton(
            systemName: micState == .recording ? "stop.fill" : "mic.fill",
            label: micState == .recording ? "Stop listening" : "Talk to Loci",
            prominent: micState == .recording,
            action: { Task { await controller.toggleMic() } }
          )
          .disabled(micState == .transcribing)
        }
        if controller.asking {
          AskLociRoundButton(systemName: "stop.circle", label: "Stop the answer", action: controller.stop)
        } else {
          AskLociRoundButton(systemName: "arrow.up", label: "Send", prominent: canSend, action: send)
            .disabled(!canSend)
        }
      }
    }
    .padding(.horizontal, LociTheme.defaultPadding)
    .padding(.top, 8)
    .padding(.bottom, 12)
  }

  private func send() {
    guard canSend else { return }
    controller.ask(text, voice: false)
    text = ""
  }
}

private struct AskLociRoundButton: View {
  let systemName: String
  let label: String
  var prominent = false
  let action: () -> Void

  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(prominent ? Color.museUserText : Color.museText)
        .frame(width: LociTheme.minTapTarget, height: LociTheme.minTapTarget)
        .background(prominent ? Color.museUserBubble : Color.musePill, in: Circle())
        .opacity(isEnabled ? 1 : 0.5)
    }
    .accessibilityLabel(label)
  }
}
