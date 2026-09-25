import SwiftUI

/// Every stop of the day with where it stands; tap one to walk there.
struct WalkStopList: View {
  let walk: StopWalk
  let onPick: (Int) -> Void

  var body: some View {
    NavigationStack {
      List(Array(walk.stops.enumerated()), id: \.element.id) { i, stop in
        Button {
          onPick(i)
        } label: {
          HStack(spacing: 12) {
            Text("\(i + 1)").font(.lociHeadline(14)).frame(width: 24)
            Text(stop.name).foregroundStyle(Color.lociInk).strikethrough(walk.skipped.contains(i))
            Spacer()
            Text(status(i)).lociCoordStyle(10)
          }
        }
      }
      .navigationTitle(walk.day?.title ?? "Stops")
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private func status(_ i: Int) -> String {
    if walk.visited.contains(i) { return "Done" }
    if walk.skipped.contains(i) { return "Skipped" }
    if i == walk.index, walk.phase == .walking { return "Walking" }
    if i == walk.upcoming, walk.phase == .arrived { return "Next" }
    return ""
  }
}
