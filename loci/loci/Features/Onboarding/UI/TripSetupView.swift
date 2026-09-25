import SwiftUI

/// The first-run questionnaire (web: routes/trip-setup.tsx): budget, pace,
/// getting around, interests. Four screens, one profile, Skip on every one.
/// `onFinish` runs after a successful save or a skip, never after a failed save.
struct TripSetupView: View {
  @State private var store: TripSetupStore
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            question("What's your budget?", subtitle: "We'll tune recommendations to match.")
            choiceGrid(
              TripSetup.Budget.allCases, isSelected: { $0.rawValue == store.answers.budget }, label: \.label, hint: \.hint, symbol: \.symbol
            ) {
              store.answers.budget = $0.rawValue
            }
          case .pace:
            question("How packed should days be?")
            choiceGrid(TripSetup.Pace.allCases, isSelected: { $0 == store.answers.pace }, label: \.label, hint: \.hint, symbol: \.symbol) {
              store.answers.pace = $0
            }
          case .mobility:
            question("How will you get around?")
            choiceGrid(TripSetup.Mobility.allCases, isSelected: { $0 == store.answers.mobility }, label: \.label, hint: nil, symbol: \.symbol) {
              store.answers.mobility = $0
            }
          case .interests:
            question("What are you into?", subtitle: "Pick a few. You can change these later in Profile › Travel profiles.")
            interests
          }
          if let error = store.error { saveError(error) }
        }
        .padding(.horizontal, LociTheme.defaultPadding)
        .padding(.bottom, 8)
      }
      .scrollBounceBehavior(.basedOnSize)
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
        Text("Step \(store.step.rawValue + 1) of \(TripSetupStore.Step.allCases.count)").lociCoordStyle(11)
        Spacer()
        Button("Skip") { store.skip() }
          .font(.lociBody(15))
          .tint(Color.lociMutedInk)
          .frame(minWidth: LociTheme.minTapTarget, minHeight: LociTheme.minTapTarget)
          .disabled(store.isSaving)
      }
      ProgressView(value: store.progress)
        .tint(Color.lociForest)
        .accessibilityLabel("Step \(store.step.rawValue + 1) of \(TripSetupStore.Step.allCases.count)")
    }
    .padding(.horizontal, LociTheme.defaultPadding)
    .padding(.top, 8)
  }

  private func question(_ title: String, subtitle: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.lociTitle(26)).foregroundStyle(Color.lociInk)
        .accessibilityAddTraits(.isHeader)
      if let subtitle { Text(subtitle).font(.lociBody(15)).foregroundStyle(Color.lociMutedInk) }
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  /// Two columns; one at accessibility text sizes so labels never truncate.
  private var columns: [GridItem] {
    dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 12), GridItem(.flexible())]
  }

  private func choiceGrid<Choice: Identifiable>(
    _ choices: [Choice],
    isSelected: @escaping (Choice) -> Bool,
    label: KeyPath<Choice, String>,
    hint: KeyPath<Choice, String>?,
    symbol: KeyPath<Choice, String>,
    select: @escaping (Choice) -> Void
  ) -> some View {
    LazyVGrid(columns: columns, spacing: 12) {
      ForEach(choices) { choice in
        let selected = isSelected(choice)
        Button { select(choice) } label: {
          VStack(alignment: .leading, spacing: 6) {
            Image(systemName: choice[keyPath: symbol]).font(.title2).foregroundStyle(Color.lociForest)
              .accessibilityHidden(true)
            Text(choice[keyPath: label]).font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
            if let hint { Text(choice[keyPath: hint]).font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk) }
          }
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
          .padding(14)
          .background(
            selected ? Color.lociSage.opacity(0.45) : Color.lociCard,
            in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous)
          )
          .overlay(
            RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous)
              .strokeBorder(selected ? Color.lociForest : Color.lociBorder, lineWidth: selected ? 2 : 1)
          )
          .contentShape(RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
    .sensoryFeedback(.selection, trigger: choices.firstIndex(where: isSelected))
  }

  @ViewBuilder private var interests: some View {
    switch store.catalogueState {
    case .loading:
      HStack(spacing: 10) {
        ProgressView()
        Text("Loading interests…").font(.lociBody(15)).foregroundStyle(Color.lociMutedInk)
      }
      .frame(minHeight: LociTheme.minTapTarget)
    case .failed:
      VStack(alignment: .leading, spacing: 8) {
        Text("We couldn't load interests. You can finish without them and add some later in your profile.")
          .font(.lociBody(15)).foregroundStyle(Color.lociDestructive)
          .fixedSize(horizontal: false, vertical: true)
        Button("Try again") { Task { await store.load() } }
          .font(.lociBody(15).weight(.semibold))
          .tint(Color.lociForest)
          .frame(minHeight: LociTheme.minTapTarget)
      }
      .accessibilityElement(children: .contain)
    case .loaded:
      FlowLayout(spacing: 8) {
        ForEach(store.chips, id: \.self) { chip in
          let on = store.answers.interests.contains(chip)
          Button { store.toggle(chip) } label: {
            Text(chip)
              .font(.lociBody(15).weight(on ? .semibold : .regular))
              .foregroundStyle(on ? Color.lociPaper : Color.lociInk)
              .padding(.horizontal, 16)
              .frame(minHeight: LociTheme.minTapTarget)
              .background(on ? Color.lociForest : Color.lociCard, in: Capsule())
              .overlay(Capsule().strokeBorder(on ? Color.clear : Color.lociBorder))
              .contentShape(Capsule())
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(on ? .isSelected : [])
        }
      }
      .sensoryFeedback(.selection, trigger: store.answers.interests)
    }
  }

  private func saveError(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(message).font(.lociBody(15)).foregroundStyle(Color.lociInk)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 20) {
        Button("Try again") { Task { await store.save() } }
          .font(.lociBody(15).weight(.semibold))
          .tint(Color.lociForest)
        Button("Skip for now") { store.skip() }
          .font(.lociBody(15))
          .tint(Color.lociMutedInk)
      }
      .frame(minHeight: LociTheme.minTapTarget)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.lociDestructive.opacity(0.1), in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous).strokeBorder(Color.lociDestructive.opacity(0.4)))
    .accessibilityElement(children: .contain)
  }

  private var footer: some View {
    HStack {
      Button("Back") { store.back() }
        .font(.lociBody(16))
        .tint(Color.lociMutedInk)
        .frame(minWidth: LociTheme.minTapTarget, minHeight: LociTheme.minTapTarget)
        .opacity(store.step == .budget ? 0 : 1)
        .disabled(store.step == .budget || store.isSaving)
        .accessibilityHidden(store.step == .budget)
      Spacer()
      Button {
        Task { await store.next() }
      } label: {
        Text(store.isLast ? (store.isSaving ? "Saving…" : "Start planning") : "Next")
          .font(.lociHeadline(17).weight(.semibold))
          .foregroundStyle(Color.lociPaper)
          .padding(.horizontal, 20)
          .frame(minWidth: 160, minHeight: 50)
      }
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.capsule)
      .tint(Color.lociForest)
      .disabled(!store.canContinue || store.isSaving)
    }
    .padding(.horizontal, LociTheme.defaultPadding)
    .padding(.bottom, 8)
  }
}
