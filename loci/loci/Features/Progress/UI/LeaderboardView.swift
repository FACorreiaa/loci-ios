import LociConnectProto
import SwiftUI

/// You and your friends, ranked (web: /friends?tab=leaderboard). Friends only:
/// nobody else is on it, and anyone can leave it in Notifications settings.
struct LeaderboardView: View {
  @State private var store: ProgressStore
  @State private var showsInvite = false
  private let feedback = PointsFeedback.shared

  init(store: ProgressStore = ProgressStore()) {
    _store = State(initialValue: store)
  }

  var body: some View {
    List {
      Section {
        Picker("Period", selection: $store.period) {
          ForEach([Loci_Gamification_LeaderboardPeriod.week, .month, .allTime], id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        Picker("Ranked by", selection: $store.metric) {
          ForEach([Loci_Gamification_LeaderboardMetric.points, .cities, .places], id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

      switch store.phase {
      case .loading:
        Section { ProgressView() }.listRowBackground(Color.lociCard)
      case .failed(let message):
        Section { Text(message).font(.lociCaption()).foregroundStyle(Color.lociMutedInk) }.listRowBackground(Color.lociCard)
      case .loaded:
        Section {
          ForEach(store.entries, id: \.user.id) { entry in
            LeaderboardRow(entry: entry, metric: store.metric)
              .listRowBackground(entry.isMe ? Color.lociCoral.opacity(0.12) : Color.lociCard)
          }
        } footer: {
          Text("Only you and your friends are ranked here.")
        }
        if store.isAlone { inviteSection }
      }
    }
    .settingsStyle("Leaderboard")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Invite", systemImage: "person.badge.plus") { showsInvite = true }
      }
    }
    .sheet(isPresented: $showsInvite) { InviteSheet() }
    .errorAlert($store.error)
    .refreshable { await store.load() }
    // One task per board: a newer period, metric or award cancels the older
    // request, so a slow answer can't overwrite a newer one. The first run is
    // the full load; later ones only re-rank.
    .task(id: BoardQuery(period: store.period, metric: store.metric, revision: feedback.revision)) {
      if store.phase == .loading { await store.load() } else { await store.reloadBoard() }
    }
    .onAppear { Analytics.screen("Leaderboard") }
  }

  private struct BoardQuery: Equatable {
    let period: Loci_Gamification_LeaderboardPeriod
    let metric: Loci_Gamification_LeaderboardMetric
    let revision: Int
  }

  private var inviteSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 10) {
        Text("Compete with friends").font(.lociHeadline())
        Text("Send your invite link: everyone who opens it joins your leaderboard. Find more people from your contacts on the Friends page.")
          .font(.lociCaption(14)).foregroundStyle(Color.lociMutedInk)
        Button("Send invite link", systemImage: "square.and.arrow.up") { showsInvite = true }
          .buttonStyle(.borderedProminent).tint(.lociCoralFill)
      }
      .padding(.vertical, 6)
    }
    .listRowBackground(Color.lociCard)
  }
}

/// One person on the board: rank, who, level and streak, and their score.
struct LeaderboardRow: View {
  let entry: Loci_Gamification_LeaderboardEntry
  let metric: Loci_Gamification_LeaderboardMetric

  var body: some View {
    HStack(spacing: 12) {
      Text("\(entry.rank)")
        .font(.lociHeadline(entry.rank <= 3 ? 20 : 16))
        .foregroundStyle(entry.rank == 1 ? Color.lociCoral : Color.lociInk)
        .frame(minWidth: 28)
      UserAvatar(user: entry.user, size: 36)
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.isMe ? "You" : entry.user.shownName).font(.lociHeadline(16)).foregroundStyle(Color.lociInk).lineLimit(1)
        HStack(spacing: 8) {
          Text("Level \(entry.level)")
          if entry.currentStreak > 0 {
            Label("\(entry.currentStreak)", systemImage: "flame.fill").labelStyle(.titleAndIcon).foregroundStyle(Color.lociCoral)
          }
        }
        .font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      }
      Spacer(minLength: 8)
      Text(metric.format(entry.value)).font(.lociHeadline(15)).foregroundStyle(Color.lociInk).monospacedDigit()
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}
