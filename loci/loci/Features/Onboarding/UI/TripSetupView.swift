import SwiftUI

/// The first-run questionnaire (web: routes/trip-setup.tsx): budget, pace,
/// getting around, interests. Four screens, one profile, Skip on every one.
struct TripSetupView: View {
  @State private var store: TripSetupStore
  let onFinish: () -> Void

  init(store: TripSetupStore = TripSetupStore(), onFinish: @escaping () -> Void) {
    _store = State(initialValue: store)
    self.onFinish = onFinish
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      header
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          switch store.step {
          case .budget:
            question("What's your budget?", subtitle: "Rough is fine; it shapes the picks.")
            choiceGrid(TripSetup.Budget.allCases, selected: store.answers.budget, label: \.label, hint: \.hint, symbol: \.symbol) {
              store.answers.budget = $0.rawValue
            }
          case .pace:
            question("How packed should days be?")
            choiceGrid(TripSetup.Pace.allCases, selected: store.answers.pace, label: \.label, hint: \.hint, symbol: \.symbol) {
              store.answers.pace = $0
            }
          case .mobility:
            question("How will you get around?")
            choiceGrid(TripSetup.Mobility.allCases, selected: store.answers.mobility, label: \.label, hint: nil, symbol: \.symbol) {
              store.answers.mobility = $0
            }
          case .interests:
            question("What are you into?", subtitle: "Pick a few. You can change these later in Profile › Travel profiles.")
            interestChips
          }
          if let error = store.error {
            VStack(alignment: .leading, spacing: 8) {
              Text(error).font(.lociCaption(13)).foregroundStyle(Color.lociDestructive)
              Button("Try again") { Task { await store.save() } }.font(.lociCaption(13).weight(.semibold)).tint(Color.lociForest)
            }
            .padding(12)
            .background(Color.lociDestructive.opacity(0.08), in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
          }
        }
        .padding(.horizontal, LociTheme.defaultPadding)
      }
      footer
    }
    .background(Color.lociPaper.ignoresSafeArea())
    .task { await store.load() }
    .onChange(of: store.isDone) { _, done in if done { onFinish() } }
    .onAppear { Analytics.screen("trip_setup") }
    .interactiveDismissDisabled()
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Step \(store.step.rawValue + 1) of \(TripSetupStore.Step.allCases.count)").lociCoordStyle(10)
        Spacer()
        Button("Skip") { onFinish() }.font(.lociCaption(13)).tint(Color.lociMutedInk)
      }
      ProgressView(value: store.progress).tint(Color.lociForest)
    }
    .padding([.horizontal, .top], LociTheme.defaultPadding)
  }

  private func question(_ title: String, subtitle: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.lociTitle(22)).foregroundStyle(Color.lociInk)
      if let subtitle { Text(subtitle).font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk) }
    }
  }

  private func choiceGrid<Choice: Identifiable & Equatable>(
    _ choices: [Choice],
    selected: some Equatable,
    label: KeyPath<Choice, String>,
    hint: KeyPath<Choice, String>?,
    symbol: KeyPath<Choice, String>,
    select: @escaping (Choice) -> Void
  ) -> some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
      ForEach(choices) { choice in
        let isSelected = isSelected(choice, selected)
        Button { select(choice) } label: {
          VStack(alignment: .leading, spacing: 6) {
            Image(systemName: choice[keyPath: symbol]).font(.title2).foregroundStyle(Color.lociForest)
            Text(choice[keyPath: label]).font(.lociBody(15).weight(.medium)).foregroundStyle(Color.lociInk)
            if let hint { Text(choice[keyPath: hint]).font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk) }
          }
          .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
          .padding(12)
          .background(Color.lociCard, in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous)
              .stroke(isSelected ? Color.lociForest : Color.lociBorder, lineWidth: isSelected ? 2 : 1)
          )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
  }

  /// Budget selects by raw value, the others by case; one comparison covers both.
  private func isSelected<Choice: Identifiable>(_ choice: Choice, _ selected: some Equatable) -> Bool {
    if let budget = choice as? TripSetup.Budget, let value = selected as? Int { return budget.rawValue == value }
    if let pace = choice as? TripSetup.Pace, let value = selected as? TripSetup.Pace { return pace == value }
    if let mobility = choice as? TripSetup.Mobility, let value = selected as? TripSetup.Mobility { return mobility == value }
    return false
  }

  private var interestChips: some View {
    FlowLayout(spacing: 8) {
      ForEach(store.chips, id: \.self) { chip in
        let on = store.answers.interests.contains(chip)
        Button(chip) { store.toggle(chip) }
          .font(.lociCaption(13).weight(on ? .semibold : .regular))
          .buttonStyle(.bordered)
          .tint(on ? Color.lociForest : Color.lociMutedInk)
          .accessibilityAddTraits(on ? .isSelected : [])
      }
    }
  }

  private var footer: some View {
    HStack {
      Button("Back") { store.back() }
        .font(.lociBody(15))
        .tint(Color.lociMutedInk)
        .opacity(store.step == .budget ? 0 : 1)
        .disabled(store.step == .budget)
      Spacer()
      Button {
        Task { await store.next() }
      } label: {
        Text(store.isLast ? (store.isSaving ? "Saving…" : "Start planning") : "Next")
          .font(.lociBody(15).weight(.semibold))
          .foregroundStyle(Color.lociPaper)
          .frame(minWidth: 140, minHeight: LociTheme.minTapTarget)
      }
      .buttonStyle(.borderedProminent)
      .tint(Color.lociForest)
      .disabled(!store.canContinue || store.isSaving)
    }
    .padding(LociTheme.defaultPadding)
  }
}
