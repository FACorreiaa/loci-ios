import LociConnectProto
import SwiftUI

/// One field report about one place (web: ClaimForm, FieldPicker,
/// ClaimResult). The scout picks from a fixed vocabulary, so two scouts who
/// saw the same thing send the same string: the only way the server can
/// corroborate them.
struct ClaimFormView: View {
  @State private var store: ClaimFormStore

  init(store: ClaimFormStore) {
    _store = State(initialValue: store)
  }

  init(task: VerificationTask, service: ContributeService = ConnectContributeService(), onSubmitted: (() -> Void)? = nil) {
    let store = ClaimFormStore(task: task, service: service)
    store.onSubmitted = onSubmitted
    _store = State(initialValue: store)
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Field report").font(.lociCoord(10)).textCase(.uppercase).tracking(1.2).foregroundStyle(Color.lociCoral)
            Text(store.task.poiName).font(.lociTitle(24)).foregroundStyle(Color.lociInk)
          }
          if store.task.requestedFields.isEmpty {
            Text("Everything we ask about this place is already covered. Pick another.")
              .font(.lociBody(15)).foregroundStyle(Color.lociMutedInk)
          } else {
            fieldPicker
            if let field = store.field { answer(for: field) }
            note
            submitButton
            if let result = store.result {
              ClaimResultCard(outcome: ClaimOutcome(result.status))
                .id("result")
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
          }
        }
        .padding(LociTheme.defaultPadding)
        .animation(.smooth, value: store.result)
      }
      .onChange(of: store.result) { _, result in
        if result != nil { withAnimation(.smooth) { proxy.scrollTo("result", anchor: .bottom) } }
      }
    }
    .background(Color.lociPaper.ignoresSafeArea())
    .navigationTitle("Report a fact")
    .navigationBarTitleDisplayMode(.inline)
    .errorAlert($store.error)
    .sensoryFeedback(.success, trigger: store.result) { _, new in new != nil }
    .onAppear { Analytics.screen("claim_form", ["fields": store.task.requestedFields.count]) }
  }

  private var fieldPicker: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("What did you verify?").font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
      FlowLayout(spacing: 8) {
        ForEach(store.task.requestedFields, id: \.self) { field in
          ContributeChip(label: PlaceFactVocabulary.label(field), isOn: store.field == field) {
            withAnimation(.snappy) { store.select(field) }
          }
        }
      }
    }
  }

  @ViewBuilder private func answer(for field: Loci_Place_PlaceFactField) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(PlaceFactVocabulary.question(field)).font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
      if store.isStructured {
        OpeningHoursEditor(hours: $store.hours)
          .lociCard(padding: 12)
        if store.hours == store.submittedHours {
          Text("This week is already filed. Change it to file again.").font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
        }
      } else if let vocabulary = store.vocabulary {
        FlowLayout(spacing: 8) {
          ForEach(vocabulary.options, id: \.token) { option in
            ContributeChip(label: option.label, isOn: store.tokens.contains(option.token)) {
              store.toggle(option.token)
            }
          }
        }
        if let cap = vocabulary.maxSelections, vocabulary.kind == .multi {
          Text("\(store.tokens.count) of \(cap) picked").font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk).monospacedDigit()
        }
      }
    }
    .id(field)
  }

  private var note: some View {
    Label {
      Text("Reports expire as places change. Your reputation grows when another scout corroborates your observation.")
    } icon: {
      Image(systemName: "checkmark.shield")
    }
    .font(.lociCaption(12))
    .foregroundStyle(Color.lociInk)
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.lociSage.opacity(0.5), in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
  }

  private var submitButton: some View {
    Button {
      Task { await store.submit() }
    } label: {
      Label(store.isSubmitting ? "Submitting…" : "Submit field report", systemImage: "checkmark.circle")
        .font(.lociBody(16).weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: LociTheme.minTapTarget)
    }
    .lociProminentButton()
    .disabled(!store.isReady || store.isSubmitting)
  }
}

/// What happened to the report just filed (web: ClaimResult). A fact needs two
/// independent scouts, so a first report is half a fact, and it says so.
struct ClaimResultCard: View {
  let outcome: ClaimOutcome

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: symbol).font(.title2).foregroundStyle(tint)
      Text(title).font(.lociHeadline(16)).foregroundStyle(tint)
      Text(detail).font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk).multilineTextAlignment(.center)
      if case .recorded = outcome {
        ScoutsBar(filled: 1, total: 2).padding(.top, 6)
      }
    }
    .frame(maxWidth: .infinity)
    .lociCard()
    .accessibilityElement(children: .combine)
  }

  private var title: String {
    switch outcome {
    case .verified: "Verified."
    case .contradicted: "Noted — reports differ."
    case .recorded: "Recorded."
    }
  }

  private var detail: String {
    switch outcome {
    case .verified: "Another scout saw the same thing. This is on the field guide now."
    case .contradicted: "Another scout saw something different. We will wait for a third look."
    case .recorded: "One more scout needs to see the same thing before it goes live."
    }
  }

  private var symbol: String {
    switch outcome {
    case .verified: "checkmark.shield.fill"
    case .contradicted: "exclamationmark.circle"
    case .recorded(let pending): pending ? "clock" : "checkmark.circle"
    }
  }

  private var tint: Color {
    if case .verified = outcome { return Color.lociForest }
    return Color.lociInk
  }
}

/// "1 of 2 scouts": two segments, the filled ones in forest.
struct ScoutsBar: View {
  let filled: Int
  let total: Int

  var body: some View {
    VStack(spacing: 4) {
      HStack(spacing: 4) {
        ForEach(0..<total, id: \.self) { index in
          Capsule().fill(index < filled ? Color.lociForest : Color.lociBorder).frame(height: 4)
        }
      }
      .frame(width: 64)
      Text("\(filled) of \(total) scouts").lociCoordStyle(10)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(filled) of \(total) scouts")
  }
}

/// A toggle chip in the app's chip style (ChipGrid's look), for one tap = one choice.
struct ContributeChip: View {
  let label: String
  let isOn: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(label)
        .font(.lociCaption(14))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minHeight: 36)
        .background(isOn ? Color.lociForest : Color.lociMuted, in: Capsule())
        .foregroundStyle(isOn ? Color.lociPaper : Color.lociInk)
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isOn ? .isSelected : [])
    .sensoryFeedback(.selection, trigger: isOn)
  }
}
