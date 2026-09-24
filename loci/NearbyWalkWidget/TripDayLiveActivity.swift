import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen and Dynamic Island for a trip day: the stop you are at with
/// the time the plan gives it, and what comes next.
struct TripDayLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: TripDayAttributes.self) { context in
      TripDayLockScreen(state: context.state, attributes: context.attributes)
        .activityBackgroundTint(Palette.paper)
        .activitySystemActionForegroundColor(Palette.forest)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.state.currentName).font(.headline).foregroundStyle(Palette.ink).lineLimit(1)
        }
        DynamicIslandExpandedRegion(.trailing) {
          TripDayCountdown(state: context.state).font(.headline).foregroundStyle(Palette.ink)
        }
        DynamicIslandExpandedRegion(.bottom) {
          if let next = context.state.nextText {
            Label(next, systemImage: "arrow.turn.down.right").font(.subheadline).foregroundStyle(Palette.terracotta).lineLimit(1)
          } else {
            Text(context.state.phase == .done ? "Day complete" : "Last stop of the day").font(.subheadline).foregroundStyle(.secondary)
          }
        }
      } compactLeading: {
        Image(systemName: "mappin.and.ellipse").foregroundStyle(Palette.terracotta)
      } compactTrailing: {
        TripDayCountdown(state: context.state).font(.caption.monospacedDigit())
      } minimal: {
        Image(systemName: "mappin.and.ellipse").foregroundStyle(Palette.terracotta)
      }
    }
  }
}

/// Counts down to the slot's end; "Done" once the day is over.
private struct TripDayCountdown: View {
  let state: TripDayAttributes.ContentState

  var body: some View {
    if state.phase == .done {
      Text("Done")
    } else {
      Text(timerInterval: Date()...max(state.slotEnd, Date()), countsDown: true)
    }
  }
}

private struct TripDayLockScreen: View {
  let state: TripDayAttributes.ContentState
  let attributes: TripDayAttributes

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Day in \(attributes.cityName) · \(state.progressText(of: attributes.stopCount))", systemImage: "suitcase")
          .font(.caption.weight(.medium)).foregroundStyle(Palette.forest)
        Spacer()
        if state.phase != .done {
          TripDayCountdown(state: state).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
      }
      Text(state.phase == .done ? "Day complete" : state.currentName).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
      if let next = state.nextText {
        Label(next, systemImage: "arrow.turn.down.right").font(.subheadline).foregroundStyle(Palette.terracotta).lineLimit(1)
      }
    }
    .padding(16)
  }
}
