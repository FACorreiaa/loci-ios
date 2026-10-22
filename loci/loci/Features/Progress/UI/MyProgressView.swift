import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Your Field rank, this week, the weekly streak, achievements and where the
/// points came from (web: /field).
struct MyProgressView: View {
  @State private var store: ProgressStore
  /// The year in review, once the server says it is ready.
  @State private var readyYear: Int?
  private let feedback = PointsFeedback.shared
  private let recaps: any RecapService

  init(store: ProgressStore = ProgressStore(), recaps: any RecapService = ConnectRecapService()) {
    _store = State(initialValue: store)
    self.recaps = recaps
  }

  var body: some View {
    List {
      if let readyYear {
        Section {
          NavigationLink(value: AppRoute.yearRecap(year: readyYear)) {
            Label("Your \(String(readyYear)) in Loci", systemImage: "sparkles").font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
          }
        }.listRowBackground(Color.lociCard)
      }
      switch store.phase {
      case .loading:
        Section { ProgressView() }.listRowBackground(Color.lociCard)
      case .failed(let message):
        Section { Text(message).font(.lociCaption()).foregroundStyle(Color.lociMutedInk) }.listRowBackground(Color.lociCard)
      case .loaded:
        if let field = store.field {
          Section {
            FieldRankCard(field: field)
            WeekStreakCard(streak: field.weekStreak)
          }
          .listRowBackground(Color.lociCard)
        }
        Section {
          NavigationLink(value: AppRoute.you(.achievements)) { Label("Achievements", systemImage: "rosette") }
          NavigationLink(value: AppRoute.you(.leaderboard)) { Label("Leaderboard", systemImage: "trophy") }
        }
        .listRowBackground(Color.lociCard)
        if let progress = store.progress {
          Section("Today") { TodayChecklistRows(today: progress.today) }.listRowBackground(Color.lociCard)
        }
        historySection
      }
    }
    .settingsStyle("Your progress")
    .errorAlert($store.error)
    .refreshable { await store.load() }
    // Reloads after an award; a newer award cancels the older reload.
    .task(id: feedback.revision) { await store.load() }
    .onAppear { Analytics.screen("Progress") }
    .task { await loadYear() }
  }

  /// One call: the row shows only when the year's recap is ready to play.
  private func loadYear() async {
    let year = RecapRules.reviewYear()
    guard let recap = try? await recaps.yearInReview(year: year), recap.status == .ready, !RecapRules.playable(recap.cards).isEmpty else { return }
    readyYear = year
  }

  @ViewBuilder private var historySection: some View {
    Section("Points") {
      if store.events.isEmpty {
        Text("Check in, search, and walk your trips to earn points.").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      }
      ForEach(store.events, id: \.id) { event in
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(event.label).font(.lociCaption(15)).foregroundStyle(Color.lociInk).lineLimit(2)
            Text(event.createdAt.date.formatted(.relative(presentation: .named))).font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
          }
          Spacer()
          Text("+\(event.points)").font(.lociHeadline(15)).foregroundStyle(Color.lociForest).monospacedDigit()
        }
      }
      if !store.nextPageToken.isEmpty {
        Button("Show more") { Task { await store.loadMoreHistory() } }
      }
    }
    .listRowBackground(Color.lociCard)
  }
}

/// The Field rank, the score, and the bar to the next rank (web: /field's rank card).
struct FieldRankCard: View {
  let field: Loci_Gamification_FieldProfile

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(field.overallRank.title).font(.lociTitle(26)).foregroundStyle(Color.lociInk)
        Spacer()
        Text("\(field.lifetimeScore.formatted()) field score").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      }
      ProgressView(value: field.rankFraction).tint(.lociCoral)
      HStack {
        Text("This week: \(field.weekScore.formatted())")
        Spacer()
        if let next = field.overallRank.next, field.overallNextThreshold > field.lifetimeScore {
          Text("\((field.overallNextThreshold - field.lifetimeScore).formatted()) to \(next.title)")
        }
      }
      .font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
  }
}

/// Weeks in a row with something explored (a place kept, a stop walked, a
/// day finished), and whether this week counts yet.
struct WeekStreakCard: View {
  let streak: Loci_Gamification_WeekStreak

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: streak.current > 0 ? "flame.fill" : "flame")
        .font(.title2).foregroundStyle(streak.current > 0 ? Color.lociCoral : Color.lociMutedInk)
      VStack(alignment: .leading, spacing: 2) {
        Text(streak.line).font(.lociCaption(15)).foregroundStyle(Color.lociInk)
        if streak.longest > streak.current {
          Text("Longest: ^[\(streak.longest) week](inflect: true)").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
        }
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }
}

struct TodayChecklistRows: View {
  let today: Loci_Gamification_TodayChecklist

  var body: some View {
    row("Opened Loci", done: today.checkedIn, points: "+5")
    row("Searched a trip", done: today.searched, points: "+5")
    row(placesTitle, done: today.placesVisited > 0, points: "+10 each")
  }

  private var placesTitle: String {
    switch today.placesVisited {
    case 0: "Visit a place with Near me"
    case 1: "Visited 1 place"
    default: "Visited \(today.placesVisited) places"
    }
  }

  private func row(_ title: String, done: Bool, points: String) -> some View {
    HStack {
      Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? Color.lociForest : Color.lociMutedInk)
      Text(title).font(.lociCaption(15)).foregroundStyle(Color.lociInk)
      Spacer()
      Text(points).font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
    }
    .accessibilityElement(children: .combine)
    .accessibilityValue(done ? "Done" : "Not yet")
  }
}

/// Profile's subtitle: Field rank, score and weekly streak, loaded once per visit.
struct ProgressSummaryLine: View {
  var service: any ProgressService = DesignPreview.requested == nil ? ConnectProgressService() : PreviewProgressService()
  @State private var field: Loci_Gamification_FieldProfile?
  private let feedback = PointsFeedback.shared

  var body: some View {
    Group {
      if let field {
        HStack(spacing: 8) {
          Text("\(field.overallRank.title) · \(field.lifetimeScore.formatted())")
          if field.weekStreak.current > 0 {
            Label("\(field.weekStreak.current)w", systemImage: "flame.fill")
              .accessibilityLabel("\(field.weekStreak.current)-week streak")
          }
        }
      } else {
        Text("Loci Explorer")
      }
    }
    .font(.subheadline).foregroundStyle(Color.lociCoral)
    .task(id: feedback.revision) { field = try? await service.fieldProfile() }
  }
}

/// The points chip over the tabs (`PointsFeedback`).
struct PointsToastOverlay: View {
  private let feedback = PointsFeedback.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack {
      if let toast = feedback.current {
        Button { feedback.dismiss() } label: {
          HStack(spacing: 8) {
            if toast.points > 0 {
              Text("+\(toast.points)").font(.lociHeadline(15)).foregroundStyle(Color.lociPaper)
            } else {
              Image(systemName: toast.symbol ?? "rosette").foregroundStyle(Color.lociPaper)
            }
            Text(toast.label).font(.lociCaption(14)).foregroundStyle(Color.lociPaper).lineLimit(1)
          }
          .padding(.horizontal, 16).padding(.vertical, 10)
          .background(Color.lociForestFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .shadow(radius: 6, y: 2)
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        .accessibilityHint("Dismisses")
      }
      Spacer()
    }
    .padding(.top, 8)
    .animation(reduceMotion ? nil : .spring(duration: 0.35), value: feedback.current)
    .allowsHitTesting(feedback.current != nil)
  }
}
