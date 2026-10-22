import LociConnectProto
import SwiftUI

/// You and who you follow, this week (web: /field?scope=friends, the
/// Following board). Anyone can leave it in Notifications settings.
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
        Picker("Ranked by", selection: $store.metric) {
          ForEach([Loci_Gamification_FieldBoardMetric.overall, .placesKept, .daysFinished], id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

      if let board = store.board {
        Section {
          if store.rows.isEmpty {
            Text("Nothing on the board this week. Mark a stop walked on one of your trips, or save a place you mean to go to.")
              .font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
          }
          ForEach(Array(store.rows.enumerated()), id: \.offset) { _, row in
            LeaderboardRow(row: row, metric: store.metric)
              .listRowBackground(row.isMe ? Color.lociCoral.opacity(0.12) : Color.lociCard)
          }
        } header: {
          Text("You and who you follow, this week")
        } footer: {
          if board.tooFew {
            Text(board.scoredUsers == 1 ? "One person on this board so far." : "\(board.scoredUsers) people on this board so far.")
          }
        }
        .listRowBackground(Color.lociCard)
        if store.isAlone { inviteSection }
      } else if case .failed(let message) = store.phase {
        Section { Text(message).font(.lociCaption()).foregroundStyle(Color.lociMutedInk) }.listRowBackground(Color.lociCard)
      } else {
        Section { ProgressView() }.listRowBackground(Color.lociCard)
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
    .refreshable { await store.loadBoard() }
    // One task per board: a newer metric or award cancels the older request,
    // so a slow answer can't overwrite a newer one.
    .task(id: BoardQuery(metric: store.metric, revision: feedback.revision)) { await store.loadBoard() }
    .onAppear { Analytics.screen("Leaderboard") }
  }

  private struct BoardQuery: Equatable {
    let metric: Loci_Gamification_FieldBoardMetric
    let revision: Int
  }

  private var inviteSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 10) {
        Text("Compete with people you follow").font(.lociHeadline())
        Text("Follow people from the People page, or send your invite link: everyone who opens it joins your board.")
          .font(.lociCaption(14)).foregroundStyle(Color.lociMutedInk)
        NavigationLink(value: AppRoute.you(.friends)) { Text("Find people").font(.lociCaption(15)) }
        Button("Send invite link", systemImage: "square.and.arrow.up") { showsInvite = true }
          .buttonStyle(.borderedProminent).tint(.lociCoralFill)
      }
      .padding(.vertical, 6)
    }
    .listRowBackground(Color.lociCard)
  }
}

/// One person on the board: position, who, Field rank, and their score.
struct LeaderboardRow: View {
  let row: Loci_Gamification_FieldBoardRow
  let metric: Loci_Gamification_FieldBoardMetric

  var body: some View {
    HStack(spacing: 12) {
      Text("\(row.position)")
        .font(.lociHeadline(row.position <= 3 ? 20 : 16))
        .foregroundStyle(row.position == 1 ? Color.lociCoral : Color.lociInk)
        .frame(minWidth: 28)
      UserAvatar(user: row.user, size: 36)
      VStack(alignment: .leading, spacing: 2) {
        Text(row.isMe ? "You" : name).font(.lociHeadline(16)).foregroundStyle(Color.lociInk).lineLimit(1)
        Text(row.rank.title).font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      }
      Spacer(minLength: 8)
      Text(metric.format(row.value)).font(.lociHeadline(15)).foregroundStyle(Color.lociInk).monospacedDigit()
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }

  private var name: String { row.displayName.isEmpty ? row.user.shownName : row.displayName }
}
