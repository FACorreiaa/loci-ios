import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Achievements (web: /achievements): tracks, moments and secrets with their
/// progress. Someone else's when opened from their profile; the server checks
/// they may be seen.
struct AchievementsView: View {
  @State private var store: AchievementsStore
  @State private var selected: Loci_Achievement_Achievement?
  @State private var showsReveal = false
  private let name: String?
  private let feedback = PointsFeedback.shared

  init(userID: String = "", name: String? = nil, store: AchievementsStore? = nil) {
    _store = State(initialValue: store ?? AchievementsStore(userID: userID))
    self.name = name
  }

  var body: some View {
    List {
      switch store.phase {
      case .loading:
        Section { ProgressView().frame(maxWidth: .infinity) }.listRowBackground(Color.lociCard)
      case .failed(let message):
        Section {
          Text(store.isOwn ? message : "These achievements are private, or could not load.")
            .font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
        }
        .listRowBackground(Color.lociCard)
      case .loaded:
        Section {
          Text("\(store.earnedCount) of \(store.total) earned. Cities, walked stops, notes, photos and reviews all count.")
            .font(.lociCaption(14)).foregroundStyle(Color.lociMutedInk)
            .padding(.horizontal, 6)
            .listRowSeparator(.hidden)
          Picker("Show", selection: $store.filter) {
            ForEach(AchievementsStore.Filter.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

        if store.filter == .next {
          Section { rows(store.shown) }.listRowBackground(Color.lociCard)
        } else {
          ForEach(store.groups, id: \.kind) { group in
            Section(group.kind.title) { rows(group.items) }.listRowBackground(Color.lociCard)
          }
        }
      }
    }
    .settingsStyle(store.isOwn ? "Achievements" : "\(name ?? "Their") achievements")
    .errorAlert($store.error)
    .refreshable { await store.load() }
    .task(id: feedback.revision) {
      await store.load()
      if store.showsReveal { showsReveal = true }
      // The "New" marks show once: a few seconds after the page shows them.
      try? await Task.sleep(for: .seconds(4))
      await store.markFreshSeen()
    }
    .sheet(item: $selected) { AchievementDetailSheet(achievement: $0) }
    .sheet(isPresented: $showsReveal, onDismiss: { Task { await store.dismissReveal() } }) {
      RevealView(count: store.unseenBackfill, achievements: store.revealed)
    }
    .onAppear { Analytics.screen("Achievements") }
  }

  private func rows(_ items: [Loci_Achievement_Achievement]) -> some View {
    ForEach(items, id: \.id) { achievement in
      Button { selected = achievement } label: { AchievementRow(achievement: achievement) }
        .buttonStyle(.plain)
    }
  }
}

nonisolated extension Loci_Achievement_Achievement: @retroactive Identifiable {}

/// One achievement with its progress: the catalogue's unit (web: AchievementCard).
struct AchievementRow: View {
  let achievement: Loci_Achievement_Achievement

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      MedallionView(achievement)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(title).font(.lociHeadline(16)).foregroundStyle(Color.lociInk).lineLimit(1)
          if achievement.isNew {
            Text("New").font(.lociCoord(9)).textCase(.uppercase).padding(.horizontal, 6).padding(.vertical, 2)
              .background(Color.lociCoralFill, in: Capsule()).foregroundStyle(.white)
          }
        }
        Text(achievement.hidden ? "Keep exploring to find out." : achievement.description_p)
          .font(.lociCaption(14)).foregroundStyle(Color.lociMutedInk).fixedSize(horizontal: false, vertical: true)
        if !achievement.hidden, achievement.nextTarget > 0 {
          HStack(spacing: 8) {
            ProgressView(value: achievement.progressShare).tint(.lociCoral)
            Text("\(min(achievement.progress, achievement.nextTarget))/\(achievement.nextTarget)")
              .font(.lociCoord(11)).foregroundStyle(Color.lociMutedInk).monospacedDigit()
          }
        }
        HStack(spacing: 10) {
          if achievement.kindValue == .track, !achievement.steps.isEmpty { TierSteps(steps: achievement.steps) }
          if let rarity = achievement.rarityLine { Text(rarity) }
        }
        .font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityValue(accessibilityValue)
  }

  private var title: String { achievement.hidden ? "Secret" : achievement.label }

  private var accessibilityValue: String {
    if achievement.isEarned { return "Earned" }
    if achievement.nextTarget > 0 { return "\(min(achievement.progress, achievement.nextTarget)) of \(achievement.nextTarget)" }
    return "Not yet"
  }
}

/// A track's four rungs as small rings: filled in the metal once reached.
struct TierSteps: View {
  let steps: [Loci_Achievement_TierStep]

  var body: some View {
    HStack(spacing: 3) {
      ForEach(steps, id: \.tier) { step in
        let tier = AchievementTier(step.tier)
        let color = MedallionView.ring(kind: .track, tier: tier)
        Text(String(tier.name.prefix(1)))
          .font(.system(size: 8, weight: .bold))
          .frame(width: 15, height: 15)
          .foregroundStyle(step.hasEarnedAt ? color : Color.lociMutedInk)
          .overlay(
            Circle().strokeBorder(step.hasEarnedAt ? color : Color.lociBorder, style: StrokeStyle(lineWidth: 1, dash: step.hasEarnedAt ? [] : [2, 2]))
          )
      }
    }
    .accessibilityLabel("Tiers: \(steps.filter(\.hasEarnedAt).count) of \(steps.count) reached")
  }
}

/// One achievement in full: every rung with its threshold and date, and rarity.
struct AchievementDetailSheet: View {
  let achievement: Loci_Achievement_Achievement
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(spacing: 10) {
            MedallionView(achievement, size: 84)
            Text(achievement.hidden ? "Secret" : achievement.label).font(.lociDisplay(22)).foregroundStyle(Color.lociInk)
              .multilineTextAlignment(.center)
            Text(achievement.hidden ? "Keep exploring to find out." : achievement.description_p)
              .font(.lociCaption(15)).foregroundStyle(Color.lociMutedInk).multilineTextAlignment(.center)
            if let rarity = achievement.rarityLine { Text(rarity).font(.lociCaption()).foregroundStyle(Color.lociMutedInk) }
            if achievement.hasEarnedAt {
              Text("Earned \(achievement.earnedAt.date.formatted(date: .abbreviated, time: .omitted))")
                .font(.lociCaption()).foregroundStyle(Color.lociForest)
            }
          }
          .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .listRowBackground(Color.lociCard)

        if achievement.kindValue == .track, !achievement.hidden, !achievement.steps.isEmpty {
          Section("Tiers") {
            ForEach(achievement.steps, id: \.tier) { step in
              let tier = AchievementTier(step.tier)
              HStack {
                MedallionView(symbol: achievement.symbol, kind: .track, tier: tier, earned: step.hasEarnedAt, size: 30)
                Text(tier.name).font(.lociHeadline(15)).foregroundStyle(Color.lociInk)
                Spacer()
                if step.hasEarnedAt {
                  Text(step.earnedAt.date.formatted(date: .abbreviated, time: .omitted)).font(.lociCaption()).foregroundStyle(Color.lociForest)
                } else {
                  Text("\(min(achievement.progress, step.threshold))/\(step.threshold)").font(.lociCoord(12)).foregroundStyle(Color.lociMutedInk)
                    .monospacedDigit()
                }
              }
              .accessibilityElement(children: .combine)
            }
          }
          .listRowBackground(Color.lociCard)
        }
      }
      .settingsStyle("")
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    .presentationDetents([.medium, .large])
  }
}
