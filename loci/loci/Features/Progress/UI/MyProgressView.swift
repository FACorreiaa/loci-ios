import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Your level, streak, today's checklist, badges and where the points came
/// from (web: /friends?tab=progress).
struct MyProgressView: View {
  @State private var store: ProgressStore
  private let feedback = PointsFeedback.shared

  init(store: ProgressStore = ProgressStore()) {
    _store = State(initialValue: store)
  }

  var body: some View {
    List {
      switch store.phase {
      case .loading:
        Section { ProgressView() }.listRowBackground(Color.lociCard)
      case .failed(let message):
        Section { Text(message).font(.lociCaption()).foregroundStyle(Color.lociMutedInk) }.listRowBackground(Color.lociCard)
      case .loaded:
        if let progress = store.progress {
          Section { LevelCard(progress: progress) }.listRowBackground(Color.lociCard)
          Section("Today") { TodayChecklistRows(today: progress.today) }.listRowBackground(Color.lociCard)
          Section("Badges") { BadgeGrid(badges: progress.badges) }.listRowBackground(Color.lociCard)
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

/// Level, total and the bar to the next level, with the streak beside it.
struct LevelCard: View {
  let progress: Loci_Gamification_Progress

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("Level \(progress.level)").font(.lociTitle(26)).foregroundStyle(Color.lociInk)
        Spacer()
        StreakBadge(days: Int(progress.currentStreak))
      }
      ProgressView(value: progress.levelFraction).tint(.lociCoral)
      HStack {
        Text("^[\(progress.totalPoints) point](inflect: true)")
        Spacer()
        Text("\(progress.pointsToNextLevel.formatted()) to level \(progress.level + 1)")
      }
      .font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      if progress.longestStreak > progress.currentStreak {
        Text("Longest streak: ^[\(progress.longestStreak) day](inflect: true)").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      }
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
  }
}

struct StreakBadge: View {
  let days: Int

  var body: some View {
    Label("^[\(days) day](inflect: true)", systemImage: days > 0 ? "flame.fill" : "flame")
      .font(.lociHeadline(15))
      .foregroundStyle(days > 0 ? Color.lociCoral : Color.lociMutedInk)
      .accessibilityLabel(days > 0 ? "\(days)-day streak" : "No streak")
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

struct BadgeGrid: View {
  let badges: [Loci_Gamification_Badge]
  @ScaledMetric(relativeTo: .title) private var symbolSize = 26.0

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
      ForEach(badges, id: \.id) { badge in
        VStack(spacing: 6) {
          Image(systemName: badge.hasAwardedAt ? "rosette" : "lock")
            .font(.system(size: symbolSize))
            .foregroundStyle(badge.hasAwardedAt ? Color.lociCoral : Color.lociMutedInk)
          Text(badge.title).font(.lociCaption(13)).foregroundStyle(Color.lociInk).multilineTextAlignment(.center)
          Text(badge.description_p).font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk).multilineTextAlignment(.center).lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(badge.hasAwardedAt ? Color.lociCoral.opacity(0.08) : Color.lociMuted.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityValue(badge.hasAwardedAt ? "Earned" : "Locked")
      }
    }
    .padding(.vertical, 6)
  }
}

/// Profile's subtitle: level, points and streak, loaded once per visit.
struct ProgressSummaryLine: View {
  var service: any ProgressService = DesignPreview.requested == nil ? ConnectProgressService() : PreviewProgressService()
  @State private var progress: Loci_Gamification_Progress?
  private let feedback = PointsFeedback.shared

  var body: some View {
    Group {
      if let progress {
        HStack(spacing: 8) {
          Text("Level \(progress.level) · \(progress.totalPoints.formatted()) pts")
          if progress.currentStreak > 0 {
            Label("\(progress.currentStreak)", systemImage: "flame.fill")
          }
        }
      } else {
        Text("Loci Explorer")
      }
    }
    .font(.subheadline).foregroundStyle(Color.lociCoral)
    .task(id: feedback.revision) { progress = try? await service.progress() }
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
              Image(systemName: "rosette").foregroundStyle(Color.lociPaper)
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
