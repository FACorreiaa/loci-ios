import SwiftUI

/// The card under the map: where you're walking to, where you are, or the
/// day's tally.
struct WalkDayCard: View {
  let walk: StopWalk
  let withoutLocation: Int
  let onEnd: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      switch walk.phase {
      case .idle:
        HStack {
          ProgressView()
          Text("Finding your way…").foregroundStyle(Color.lociMutedInk)
        }
      case .walking:
        walking
      case .arrived:
        arrived
      case .done:
        done
      }
      if withoutLocation > 0, walk.phase != .done {
        Text(withoutLocation == 1 ? "1 stop has no location and is skipped" : "\(withoutLocation) stops have no location and are skipped")
          .font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.lociPaper, in: .rect(cornerRadius: 20))
    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    .padding(.horizontal, 12)
    .animation(LociTheme.selectionSettle, value: walk.phase)
  }

  private var stopName: String { walk.stops.indices.contains(walk.index) ? walk.stops[walk.index].name : "" }

  private var walking: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text("→ \(walk.progressText) · \(stopName)").font(.lociHeadline(16)).foregroundStyle(Color.lociInk).lineLimit(1)
        Text(walkingDetail).lociCoordStyle(10).contentTransition(.numericText())
        if walk.navigator.isStraightLine {
          Text("No walking route — straight line").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
        }
      }
      Spacer()
      Button("End", systemImage: "xmark", action: onEnd).buttonStyle(.bordered).tint(.lociCoral)
    }
  }

  private var walkingDetail: String {
    let nav = walk.navigator
    guard nav.leg != nil else { return "Finding a walking route…" }
    return [
      NearbyWalkAttributes.ContentState.format(meters: nav.remainingMeters),
      NearbyWalkAttributes.ContentState.format(eta: nav.eta),
      walk.tracker.deniedByUser ? nil : walk.tracker.stepsText,
    ]
    .compactMap { $0 }
    .joined(separator: " · ")
  }

  private var arrived: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("You're at \(stopName) (\(walk.progressText))", systemImage: "flag.checkered")
        .font(.lociHeadline(16)).foregroundStyle(Color.lociForest)
      if let next = walk.upcoming {
        HStack {
          Button {
            Task { await walk.walkToNext() }
          } label: {
            Text("Walk to next: \(walk.stops[next].name)\(nextTime)").lineLimit(1)
          }
          .buttonStyle(.borderedProminent).tint(.lociForest)
          .disabled(walk.navigator.leg == nil)
          Button("Skip") { Task { await walk.skip() } }.buttonStyle(.bordered)
        }
      }
    }
  }

  private var nextTime: String {
    walk.navigator.leg == nil ? "" : " · " + NearbyWalkAttributes.ContentState.format(eta: walk.navigator.eta)
  }

  private var done: some View {
    let summary = walk.summary
    let tally = [
      "\(summary.visited) \(summary.visited == 1 ? "stop" : "stops")" + (summary.skipped > 0 ? " (\(summary.skipped) skipped)" : ""),
      NearbyWalkAttributes.ContentState.format(meters: summary.meters),
      walk.tracker.deniedByUser ? nil : walk.tracker.stepsText,
    ]
    .compactMap { $0 }
    .joined(separator: " · ")
    return HStack {
      VStack(alignment: .leading, spacing: 3) {
        Text("Day walked").font(.lociHeadline(18)).foregroundStyle(Color.lociInk)
        Text(tally).lociCoordStyle(10)
      }
      Spacer()
      Button("Done", action: onEnd).buttonStyle(.borderedProminent).tint(.lociForest)
    }
  }
}
