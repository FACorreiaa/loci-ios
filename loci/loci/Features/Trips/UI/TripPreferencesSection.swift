import LociConnectProto
import SwiftUI

/// Trip-wide constraints, collapsed by default (web: components/trip/TripPreferences.tsx).
/// They are set once and rarely touched, so the collapsed row states every
/// current value instead of keeping five controls open above the days.
struct TripPreferencesSection: View {
  let constraints: Loci_Trip_TripConstraint
  let onChange: (PreferencePatch) -> Void

  @State private var isExpanded: Bool
  @State private var mobility = ""
  @FocusState private var mobilityFocused: Bool

  /// What an unset window shows in the pickers until the traveller moves it.
  private static let defaultStart: Int32 = 9 * 60
  private static let defaultEnd: Int32 = 18 * 60

  init(constraints: Loci_Trip_TripConstraint, startsExpanded: Bool = false, onChange: @escaping (PreferencePatch) -> Void) {
    self.constraints = constraints
    self.onChange = onChange
    _isExpanded = State(initialValue: startsExpanded)
  }

  var body: some View {
    Section {
      DisclosureGroup(isExpanded: $isExpanded) {
        paceRow
        budgetRow
        mobilityRow
        TimeRow(
          title: "Day starts",
          minutes: constraints.hasDayStartMinute ? constraints.dayStartMinute : nil,
          placeholder: Self.defaultStart
        ) { onChange(.dayStart($0)) }
        TimeRow(
          title: "Day ends",
          minutes: constraints.hasDayEndMinute ? constraints.dayEndMinute : nil,
          placeholder: Self.defaultEnd
        ) { onChange(.dayEnd($0)) }
      } label: {
        summary
      }
      .tint(Color.lociForest)
    }
    .listRowBackground(Color.lociCard)
    .onAppear { mobility = constraints.hasMobility ? constraints.mobility : "" }
    .onChange(of: constraints.mobility) { _, value in if !mobilityFocused { mobility = value } }
  }

  private var summary: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label("Trip preferences", systemImage: "slider.horizontal.3")
        .font(.lociCoord(11)).foregroundStyle(Color.lociMutedInk)
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 6) { badges }
        VStack(alignment: .leading, spacing: 4) { badges }
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var badges: some View {
    ForEach(TripFormat.preferenceBadges(constraints), id: \.self) { badge in
      Text(badge)
        .font(.lociCaption(12)).foregroundStyle(Color.lociInk)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .overlay(Capsule().stroke(Color.lociBorder))
    }
  }

  private var paceRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Pace").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      Picker("Pace", selection: Binding(get: { constraints.pace }, set: { onChange(.pace($0)) })) {
        ForEach(TripFormat.paceOptions, id: \.self) { Text(TripFormat.paceLabel($0)).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
  }

  private var budgetRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Budget").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      HStack(spacing: 8) {
        ForEach(Int32(1)...4, id: \.self) { level in
          let selected = constraints.hasBudgetLevel && constraints.budgetLevel == level
          Button {
            onChange(.budget(TripFormat.toggledBudget(current: constraints.hasBudgetLevel ? constraints.budgetLevel : nil, tapped: level)))
          } label: {
            Text(TripFormat.budgetLabel(level) ?? "")
              .font(.lociCaption(14)).frame(maxWidth: .infinity, minHeight: 32)
              .foregroundStyle(selected ? LociTheme.stampInk : Color.lociInk)
              .background(selected ? Color.lociForest : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
              .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.lociBorder))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Budget level \(level)")
          .accessibilityAddTraits(selected ? .isSelected : [])
          .accessibilityHint(selected ? "Tap again to clear" : "")
        }
      }
    }
  }

  private var mobilityRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Mobility").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      TextField("walking, transit…", text: $mobility)
        .textInputAutocapitalization(.never)
        .submitLabel(.done)
        .focused($mobilityFocused)
        .onSubmit(commitMobility)
        .onChange(of: mobilityFocused) { _, focused in if !focused { commitMobility() } }
    }
  }

  private func commitMobility() {
    let current = constraints.hasMobility ? constraints.mobility : ""
    guard mobility.trimmingCharacters(in: .whitespacesAndNewlines) != current else { return }
    onChange(.mobility(mobility))
  }
}

/// One end of the day window. The picker's value is debounced, because a wheel
/// spin would otherwise send a SetConstraint per tick, each one racing the
/// last for the trip's `version`.
private struct TimeRow: View {
  let title: String
  let minutes: Int32?
  let placeholder: Int32
  let onCommit: (Int32?) -> Void

  @State private var value = Date()
  @State private var pending: Task<Void, Never>?
  /// The minutes `value` was last set to, by the trip or by the traveller.
  @State private var shown: Int32?

  var body: some View {
    HStack {
      DatePicker(title, selection: $value, displayedComponents: .hourAndMinute)
        .font(.lociBody(15))
      if minutes != nil {
        Button("Clear \(title.lowercased())", systemImage: "xmark.circle.fill") {
          pending?.cancel()
          onCommit(nil)
        }
        .labelStyle(.iconOnly).foregroundStyle(Color.lociMutedInk).buttonStyle(.plain)
      }
    }
    .onAppear { show(minutes) }
    .onChange(of: minutes) { _, new in show(new) }
    .onChange(of: value) { _, new in
      let picked = TripFormat.minutes(of: new)
      // Only a change the traveller made is sent, never the value set from the trip.
      guard picked != shown else { return }
      shown = picked
      pending?.cancel()
      pending = Task {
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        onCommit(picked)
      }
    }
  }

  private func show(_ minutes: Int32?) {
    let target = minutes ?? placeholder
    shown = target
    value = TripFormat.date(fromMinutes: target)
  }
}
